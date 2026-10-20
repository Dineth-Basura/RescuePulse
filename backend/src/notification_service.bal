import ballerina/file;
import ballerina/http;
import ballerina/io;
import ballerina/time;
import ballerina/uuid;

type Notification record {|
    string id = "";
    string channel = "in-app";
    string target = "team";
    string title;
    string body;
    string createdAt = "";
    string[] readBy = [];
|};

Notification[] notifications = [];
final string NOTIFICATIONS_PATH = dataDir + "/notifications.json";

function loadNotifications() returns error? {
    if check file:test(NOTIFICATIONS_PATH, file:EXISTS) {
        json saved = check io:fileReadJson(NOTIFICATIONS_PATH);
        notifications = check saved.cloneWithType();
    }
}

function saveNotifications() returns error? {
    check io:fileWriteJson(NOTIFICATIONS_PATH, notifications);
}

function canReadNotice(User actor, Notification notice) returns boolean {
    return notice.target == "team" || notice.target == actor.username;
}

service /notify on httpListener {
    resource function get health() returns json {
        return {status: "notification-service:ok"};
    }

    resource function post publish(http:Request req, @http:Payload Notification body) returns Notification|http:Unauthorized|http:Forbidden|http:BadRequest|error {
        lock {
            User? actor = currentUser(req);
            if actor is () {
                return <http:Unauthorized>{body: {message: "Please sign in"}};
            }
            if body.title.trim().length() == 0 || body.title.length() > 150 || body.body.trim().length() == 0 || body.body.length() > 2000 || body.channel != "in-app" || (body.target != "team" && !users.hasKey(body.target)) {
                return <http:BadRequest>{body: {message: "Check the notification title, message and recipient"}};
            }
            if actor.role != "admin" && body.target != actor.username {
                return <http:Forbidden>{body: {message: "Only coordinators can notify the workspace or another account"}};
            }
            Notification notice = {id: uuid:createType4AsString(), channel: "in-app", target: body.target, title: body.title.trim(), body: body.body.trim(), createdAt: time:utcToString(time:utcNow())};
            Notification[] previous = notifications.clone();
            notifications.push(notice);
            if notifications.length() > 1000 {
                _ = notifications.remove(0);
            }
            var saved = saveNotifications();
            if saved is error {
                notifications = previous;
                return saved;
            }
            if actor.role == "admin" { _ = auditAdmin(actor.username, "NOTIFICATION_PUBLISHED", notice.target, "Subject: " + notice.title); }
            return notice;

        }
    }

    resource function get list(http:Request req) returns Notification[]|http:Unauthorized {
        lock {
            User? actor = currentUser(req);
            if actor is () {
                return <http:Unauthorized>{body: {message: "Please sign in"}};
            }
            Notification[] out = [];
            foreach var notice in notifications {
                if canReadNotice(actor, notice) {
                    out.push(notice);
                }
            }
            return out;

        }
    }

    resource function put read/[string id](http:Request req) returns json|http:Unauthorized|http:NotFound|error {
        lock {
            User? actor = currentUser(req);
            if actor is () {
                return <http:Unauthorized>{body: {message: "Please sign in"}};
            }
            foreach int index in 0 ..< notifications.length() {
                Notification previous = notifications[index].clone();
                if previous.id == id && canReadNotice(actor, previous) {
                    if previous.readBy.indexOf(actor.username) is int {
                        return {status: "ok"};
                    }
                    notifications[index].readBy.push(actor.username);
                    var saved = saveNotifications();
                    if saved is error {
                        notifications[index] = previous;
                        return saved;
                    }
                    return {status: "ok"};
                }
            }
            return <http:NotFound>{body: {message: "Notification not found"}};

        }
    }
}
