import ballerina/crypto;
import ballerina/file;
import ballerina/http;
import ballerina/io;
import ballerina/time;
import ballerina/uuid;

configurable string dataDir = "runtime-data";
configurable string adminPassword = "";

type SignupRequest record {|
    string username;
    string password;
|};

type LoginRequest SignupRequest;

type AuthResponse record {
    string status;
    string message?;
    string token?;
    string role?;
    string username?;
};

type User record {|
    string username;
    string password;
    string role;
    boolean enabled = true;
    string createdAt = "";
    string lastLogin = "";
|};

type PasswordChange record {|
    string currentPassword;
    string newPassword;
|};

type Session record {|
    string username;
    int expires;
|};

final map<User> users = {};
final map<Session> sessions = {};
final string USERS_PATH = dataDir + "/users.json";
final string LOGIN_LOG_PATH = dataDir + "/login.txt";

function init() returns error? {
    if !(check file:test(dataDir, file:EXISTS)) {
        check file:createDir(dataDir);
    }
    if check file:test(USERS_PATH, file:EXISTS) {
        json saved = check io:fileReadJson(USERS_PATH);
        map<User> loaded = check saved.cloneWithType();
        foreach var [key, value] in loaded.entries() {
            users[key] = value;
        }
    }
    check loadAdminState();
    check loadIncidentsFromFile();
    check loadNotifications();
    check loadWeather();
    if adminPassword.length() > 0 && (adminPassword.length() < 8 || adminPassword.toBytes().length() > 72) {
        return error("adminPassword must be 8-72 bytes");
    }
    if adminPassword.length() >= 8 {
        var existing = users["admin"];
        User primary = existing is User ? existing.clone() : {username: "admin", password: "", role: "admin", createdAt: time:utcToString(time:utcNow())};
        primary.password = check crypto:hashBcrypt(adminPassword); primary.role = "admin"; primary.enabled = true;
        users["admin"] = primary;
        check saveUsers();
    }
}

function saveUsers() returns error? {
    check io:fileWriteJson(USERS_PATH, users);
}

function validUsername(string name) returns boolean {
    if name.length() < 3 || name.length() > 40 {
        return false;
    }
    foreach int c in name.toCodePointInts() {
        if !((c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95 || c == 45) {
            return false;
        }
    }
    return true;
}

function currentUser(http:Request req) returns User? {
    var header = req.getHeader("authorization");
    if header is string && header.startsWith("Bearer ") {
        string token = header.substring(7);
        var session = sessions[token];
        if session is Session {
            if session.expires > time:utcNow()[0] {
                User? user = users[session.username];
                return user is User && user.enabled ? user : ();
            }
            _ = sessions.remove(token);
        }
    }
    return ();
}

function isAdmin(http:Request req) returns boolean {
    User? user = currentUser(req);
    return user is User && user.role == "admin";
}

service /auth on httpListener {
    resource function get registration() returns json { return {enabled: adminState.policy.registrationOpen}; }

    resource function get health() returns json {
        return {status: "auth-service:ok"};
    }

    resource function post signup(@http:Payload SignupRequest req) returns AuthResponse|http:BadRequest|http:Forbidden|http:Conflict|error {
        lock {
            if !adminState.policy.registrationOpen { return <http:Forbidden>{body: {status: "error", message: "Public registration is closed. Contact your administrator."}}; }
            string name = req.username.trim().toLowerAscii();
            if !validUsername(name) || name == "admin" || req.password.length() < 8 || req.password.toBytes().length() > 72 {
                return <http:BadRequest>{body: {status: "error", message: "Use a 3-40 character username (letters, digits, _ or -) and an 8-72 byte password. Admin is reserved."}};
            }
            if users.hasKey(name) {
                return <http:Conflict>{body: {status: "error", message: "Username already exists"}};
            }
            users[name] = {username: name, password: check crypto:hashBcrypt(req.password), role: "user", createdAt: time:utcToString(time:utcNow())};
            var saved = saveUsers();
            if saved is error {
                _ = users.remove(name);
                return saved;
            }
            return {status: "ok"};

        }
    }

    resource function post login(@http:Payload LoginRequest req) returns AuthResponse|http:Unauthorized|error {
        lock {
            string name = req.username.trim().toLowerAscii();
            var user = users[name];
            if user is User && user.enabled {
                if check crypto:verifyBcrypt(req.password, user.password) {
                    User updated = user.clone(); updated.lastLogin = time:utcToString(time:utcNow()); users[name] = updated;
                    var saved = saveUsers(); if saved is error { users[name] = user; return saved; }
                    string token = uuid:createType4AsString();
                    sessions[token] = {username: name, expires: time:utcNow()[0] + 28800};
                    return {status: "ok", token, role: user.role, username: name};
                }
            }
            return <http:Unauthorized>{body: {status: "error", message: "Invalid username or password"}};

        }
    }

    resource function get me(http:Request req) returns json|http:Unauthorized {
        lock {
            User? user = currentUser(req);
            if user is User {
                return {username: user.username, role: user.role};
            }
            return <http:Unauthorized>{body: {message: "Please sign in"}};

        }
    }

    resource function put password(http:Request req, @http:Payload PasswordChange body) returns json|http:Unauthorized|http:BadRequest|error {
        lock {
            User? actor = currentUser(req);
            if actor is () {
                return <http:Unauthorized>{body: {message: "Please sign in"}};
            }
            if body.newPassword.length() < 8 || body.newPassword.toBytes().length() > 72 || body.newPassword == body.currentPassword {
                return <http:BadRequest>{body: {message: "Choose a different password of 8-72 bytes"}};
            }
            if !(check crypto:verifyBcrypt(body.currentPassword, actor.password)) {
                return <http:BadRequest>{body: {message: "Current password is incorrect"}};
            }
            User updated = actor.clone();
            updated.password = check crypto:hashBcrypt(body.newPassword);
            users[actor.username] = updated;
            var saved = saveUsers();
            if saved is error {
                users[actor.username] = actor;
                return saved;
            }
            string[] tokens = sessions.keys();
            foreach string token in tokens {
                var session = sessions[token];
                if session is Session && session.username == actor.username {
                    _ = sessions.remove(token);
                }
            }
            return {status: "ok", message: "Password updated. Sign in again on your devices."};

        }
    }

    resource function post logout(http:Request req) returns json {
        lock {
            var header = req.getHeader("authorization");
            if header is string && header.startsWith("Bearer ") {
                string token = header.substring(7);
                if sessions.hasKey(token) {
                    _ = sessions.remove(token);
                }
            }
            return {status: "ok"};

        }
    }
}
