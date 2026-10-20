import ballerina/http;

service /operations on httpListener {
    resource function get members(http:Request req) returns json|http:Unauthorized {
        lock {
            User? actor = currentUser(req);
            if actor is () {
                return <http:Unauthorized>{body: {message: "Please sign in"}};
            }
            json[] members = [];
            foreach var user in users {
                if user.enabled && user.role == "user" { members.push({username: user.username, role: user.role}); }
            }
            return {members};

        }
    }
}
