import ballerina/http;

type StatusUpdateRequest record {|
    string status;
|};

service /operations on httpListener {
    resource function get members(http:Request req) returns json|http:Unauthorized|http:Forbidden {
        lock {
            User? actor = currentUser(req);
            if actor is () {
                return <http:Unauthorized>{body: {message: "Please sign in"}};
            }
            if actor.role == "citizen" { return <http:Forbidden>{body: {message: "Responder directory is restricted"}}; }
            json[] members = [];
            foreach var user in users {
                if user.enabled && user.role == "user" {
                    members.push({username: user.username, role: user.role, status: user.status});
                }
            }
            return {members};

        }
    }

    resource function put status(http:Request req, @http:Payload StatusUpdateRequest body) returns json|http:Unauthorized|http:BadRequest|error {
        lock {
            User? actor = currentUser(req);
            if actor is () {
                return <http:Unauthorized>{body: {message: "Please sign in"}};
            }
            if body.status != "AVAILABLE" && body.status != "BUSY" {
                return <http:BadRequest>{body: {message: "Status must be AVAILABLE or BUSY"}};
            }
            User updated = actor.clone();
            updated.status = body.status;
            users[actor.username] = updated;
            var saved = saveUsers();
            if saved is error {
                users[actor.username] = actor;
                return saved;
            }
            return {status: "ok", username: actor.username, availability: updated.status};
        }
    }
}
