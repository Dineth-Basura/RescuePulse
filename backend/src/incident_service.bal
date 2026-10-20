import ballerina/file;
import ballerina/http;
import ballerina/io;
import ballerina/time;
import ballerina/uuid;

type Incident record {|
    string id = "";
    string location;
    string description;
    string severity;
    string status = "OPEN";
    string createdAt = "";
    string updatedAt = "";
    string category = "OTHER";
    string reportedBy = "";
    string assignee = "";
    string dueAt = "";
    boolean archived = false;
    int revision = 1;
    IncidentNote[] notes = [];
    IncidentEvent[] history = [];
|};

final string INCIDENTS_PATH = dataDir + "/incidents.json";
final map<Incident> incidents = {};

function loadIncidentsFromFile() returns error? {
    if check file:test(INCIDENTS_PATH, file:EXISTS) {
        json saved = check io:fileReadJson(INCIDENTS_PATH);
        map<Incident> loaded = check saved.cloneWithType();
        foreach var [key, value] in loaded.entries() {
            incidents[key] = value;
        }
    }
}

function persistIncidentsToFile() returns error? {
    check io:fileWriteJson(INCIDENTS_PATH, incidents);
}

type IncidentNote record {|
    string id;
    string author;
    string text;
    string createdAt;
|};

type IncidentEvent record {|
    string actor;
    string action;
    string createdAt;
|};

type IncidentChanges record {|
    string status?;
    string severity?;
    string location?;
    string description?;
    string category?;
    string assignee?;
    string dueAt?;
    boolean archived?;
    int revision;
|};

type NoteRequest record {|
    string text;
|};

function validCategory(string category) returns boolean {
    return category == "FLOOD" || category == "LANDSLIDE" || category == "STORM" || category == "FIRE" || category == "MEDICAL" || category == "OTHER";
}

function validDeadline(string deadline) returns boolean {
    return deadline == "" || time:utcFromString(deadline) is time:Utc;
}

function canManageIncident(User user, Incident incident) returns boolean {
    return user.role == "admin" || incident.assignee == user.username;
}

function visibleIncident(User user, Incident incident) returns boolean {
    return user.role == "admin" || incident.reportedBy == user.username || incident.assignee == user.username;
}

function saveIncidentChange(Incident previous, Incident updated) returns error? {
    incidents[updated.id] = updated;
    var saved = persistIncidentsToFile();
    if saved is error {
        incidents[previous.id] = previous;
        return saved;
    }
}

service /incident on httpListener {
    resource function get health() returns json {
        return {status: "incident-service:ok"};
    }

    resource function post create(http:Request req, @http:Payload Incident body) returns Incident|http:Unauthorized|http:BadRequest|error {
        lock {
            User? actor = currentUser(req);
            if actor is () {
                return <http:Unauthorized>{body: {message: "Please sign in"}};
            }
            if !validIncident(body) || !validCategory(body.category) {
                return <http:BadRequest>{body: {message: "Check the incident location, description, category and severity"}};
            }
            string id = "inc-" + uuid:createType4AsString();
            string now = time:utcToString(time:utcNow());
            Incident incident = {
                id,
                location: body.location.trim(),
                description: body.description.trim(),
                severity: body.severity,
                category: body.category,
                reportedBy: actor.username,
                status: "OPEN",
                createdAt: now,
                updatedAt: now,
                history: [{actor: actor.username, action: "Incident reported", createdAt: now}]
            };
            incidents[id] = incident;
            var saved = persistIncidentsToFile();
            if saved is error {
                _ = incidents.remove(id);
                return saved;
            }
            return incident;

        }
    }

    resource function patch [string id](http:Request req, @http:Payload IncidentChanges changes) returns Incident|http:Unauthorized|http:Forbidden|http:BadRequest|http:NotFound|http:Conflict|error {
        lock {
            User? actor = currentUser(req);
            if actor is () {
                return <http:Unauthorized>{body: {message: "Please sign in"}};
            }
            var previous = incidents[id];
            if previous is () {
                return <http:NotFound>{body: {message: "Incident not found"}};
            }
            if !canManageIncident(actor, previous) {
                return <http:Forbidden>{body: {message: "Only the coordinator or assigned responder can update this incident"}};
            }
            if changes.revision != previous.revision {
                return <http:Conflict>{body: {message: "This incident changed. Refresh it before saving."}};
            }
            if actor.role != "admin" && (changes.assignee is string || changes.archived is boolean || changes.dueAt is string) {
                return <http:Forbidden>{body: {message: "Assignment, deadlines and archiving require a coordinator"}};
            }
            Incident updated = previous.clone();
            updated.status = changes.status ?: previous.status;
            updated.severity = changes.severity ?: previous.severity;
            updated.location = (changes.location ?: previous.location).trim();
            updated.description = (changes.description ?: previous.description).trim();
            updated.category = changes.category ?: previous.category;
            updated.assignee = changes.assignee ?: previous.assignee;
            updated.dueAt = changes.dueAt ?: previous.dueAt;
            updated.archived = changes.archived ?: previous.archived;
            if !validIncident(updated) || !validCategory(updated.category) || !validDeadline(updated.dueAt) || (updated.assignee != "" && !users.hasKey(updated.assignee)) {
                return <http:BadRequest>{body: {message: "Invalid incident details, assignee or response deadline"}};
            }
            if updated.assignee != "" && updated.assignee != previous.assignee {
                User? assigned = users[updated.assignee];
                if assigned is User && (!assigned.enabled || assigned.role != "user") { return <http:BadRequest>{body: {message: "Assign incidents to an active responder"}}; }
            }
            if updated.archived && updated.status != "RESOLVED" {
                return <http:BadRequest>{body: {message: "Resolve an incident before archiving it"}};
            }
            if previous.archived && updated.archived {
                return <http:BadRequest>{body: {message: "Restore this incident before making changes"}};
            }
            string now = time:utcToString(time:utcNow());
            string action = "Incident details updated";
            if updated.status != previous.status {
                action = "Status changed from " + previous.status + " to " + updated.status;
            }
            if updated.assignee != previous.assignee {
                action += "; assigned to " + (updated.assignee == "" ? "unassigned" : updated.assignee);
            }
            if updated.archived != previous.archived {
                action = updated.archived ? "Incident archived" : "Incident restored";
            }
            updated.updatedAt = now;
            updated.revision += 1;
            updated.history.push({actor: actor.username, action, createdAt: now});
            check saveIncidentChange(previous, updated);
            return updated;

        }
    }

    resource function post [string id]/notes(http:Request req, @http:Payload NoteRequest body) returns Incident|http:Unauthorized|http:Forbidden|http:BadRequest|http:NotFound|error {
        lock {
            User? actor = currentUser(req);
            if actor is () {
                return <http:Unauthorized>{body: {message: "Please sign in"}};
            }
            var previous = incidents[id];
            if previous is () {
                return <http:NotFound>{body: {message: "Incident not found"}};
            }
            if !visibleIncident(actor, previous) {
                return <http:Forbidden>{body: {message: "You do not have access to this incident"}};
            }
            string text = body.text.trim();
            if text.length() == 0 || text.length() > 2000 || previous.archived {
                return <http:BadRequest>{body: {message: "Enter a note of 1-2000 characters on an active incident"}};
            }
            Incident updated = previous.clone();
            string now = time:utcToString(time:utcNow());
            updated.notes.push({id: uuid:createType4AsString(), author: actor.username, text, createdAt: now});
            updated.history.push({actor: actor.username, action: "Response note added", createdAt: now});
            updated.updatedAt = now;
            updated.revision += 1;
            check saveIncidentChange(previous, updated);
            return updated;

        }
    }

    resource function put update/[string id](http:Request req, @http:Payload Incident body) returns Incident|http:Forbidden|http:BadRequest|http:NotFound|http:Conflict|error {
        lock {
            if !isAdmin(req) {
                return <http:Forbidden>{body: {message: "Administrator access required"}};
            }
            if !validIncident(body) {
                return <http:BadRequest>{body: {message: "Invalid incident fields"}};
            }
            var previous = incidents[id];
            if previous is () {
                return <http:NotFound>{body: {message: "Incident not found"}};
            }
            if previous.revision != body.revision {
                return <http:Conflict>{body: {message: "Refresh the incident before saving"}};
            }
            if previous.archived {
                return <http:BadRequest>{body: {message: "Restore this incident before updating it"}};
            }
            Incident updated = previous.clone();
            updated.location = body.location.trim();
            updated.description = body.description.trim();
            updated.severity = body.severity;
            updated.status = body.status;
            updated.updatedAt = time:utcToString(time:utcNow());
            updated.revision += 1;
            User actor = <User>currentUser(req);
            updated.history.push({actor: actor.username, action: "Incident updated; status " + updated.status, createdAt: updated.updatedAt});
            check saveIncidentChange(previous, updated);
            return updated;

        }
    }

    resource function get [string id](http:Request req) returns Incident|http:Unauthorized|http:Forbidden|http:NotFound {
        lock {
            User? actor = currentUser(req);
            if actor is () {
                return <http:Unauthorized>{body: {message: "Please sign in"}};
            }
            var incident = incidents[id];
            if incident is Incident {
                if !visibleIncident(actor, incident) {
                    return <http:Forbidden>{body: {message: "You do not have access to this incident"}};
                }
                return incident;
            }
            return <http:NotFound>{body: {message: "Incident not found"}};

        }
    }

    resource function get list(http:Request req) returns Incident[]|http:Unauthorized {
        lock {
            User? actor = currentUser(req);
            if actor is () {
                return <http:Unauthorized>{body: {message: "Please sign in"}};
            }
            Incident[] out = [];
            foreach var incident in incidents {
                if visibleIncident(actor, incident) {
                    out.push(incident);
                }
            }
            return out;

        }
    }

    resource function delete [string id](http:Request req) returns json|http:Forbidden|http:NotFound|error {
        lock {
            if !isAdmin(req) {
                return <http:Forbidden>{body: {message: "Administrator access required"}};
            }
            var existing = incidents[id];
            if existing is () {
                return <http:NotFound>{body: {message: "Incident not found"}};
            }
            _ = incidents.remove(id);
            var saved = persistIncidentsToFile();
            if saved is error {
                incidents[id] = existing;
                return saved;
            }
            return {status: "deleted"};

        }
    }
}

function validIncident(Incident inc) returns boolean {
    return inc.location.trim().length() > 0 && inc.location.length() <= 100 &&
        inc.description.trim().length() > 0 && inc.description.length() <= 2000 &&
        !inc.location.includes("\t") && !inc.location.includes("\n") && !inc.location.includes("\r") &&
        (inc.severity == "LOW" || inc.severity == "MEDIUM" || inc.severity == "HIGH" || inc.severity == "CRITICAL") &&
        (inc.status == "OPEN" || inc.status == "ACK" || inc.status == "RESOLVED");
}
