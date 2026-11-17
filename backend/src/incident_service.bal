import ballerina/file;
import ballerina/http;
import ballerina/io;
import ballerina/log;
import ballerina/time;
import ballerina/uuid;
import ballerina/lang.'array as array;

type Incident record {|
    string id = "";
    string location;
    string description;
    string severity;
    string status = "OPEN";
    // Optional geo fields maintain compatibility with existing persisted reports.
    float? latitude = ();
    float? longitude = ();
    int affectedPeople = 0;
    boolean assistanceRequested = false;
    string verificationStatus = "PENDING";
    string verificationReason = "";
    string missionStatus = "UNASSIGNED";
    string createdAt = "";
    string updatedAt = "";
    string category = "OTHER";
    string reportedBy = "";
    string originRole = "legacy";
    string assignee = "";
    string dueAt = "";
    boolean archived = false;
    int revision = 1;
    IncidentNote[] notes = [];
    IncidentEvent[] history = [];
    string attachmentUrl = "";
    string attachmentName = "";
    string contactInfo = "";
    string completionOutcome = "";
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
    string contactInfo?;
    string completionOutcome?;
    string missionStatus?;
    int revision;
|};

type VerificationRequest record {|
    string decision;
    string reason = "";
    int revision;
|};

type MissionRequest record {|
    string action;
    int revision;
    string outcome = "";
    string evidenceUrl = "";
|};

type AttachmentUploadRequest record {|
    string filename;
    string mimeType;
    string base64Data;
|};

type NoteRequest record {|
    string text;
|};

function validImageExtension(string name) returns string? {
    string lower = name.toLowerAscii();
    if lower.endsWith(".jpg") || lower.endsWith(".jpeg") {
        return ".jpg";
    }
    if lower.endsWith(".png") {
        return ".png";
    }
    if lower.endsWith(".webp") {
        return ".webp";
    }
    return ();
}

function validMimeType(string mime) returns boolean {
    return mime == "image/jpeg" || mime == "image/png" || mime == "image/webp";
}

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

// Incident persistence is the primary operation. A failure to save the
// accompanying in-app notification must not turn a committed incident
// change into a misleading HTTP error, which could cause duplicate retries.
function notifyIncident(string target, string title, string message) {
    var result = systemNotice(target, title, message);
    if result is error {
        log:printError("Incident update succeeded, but its in-app notification could not be persisted");
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
                originRole: actor.role,
                status: "OPEN",
                latitude: body.latitude,
                longitude: body.longitude,
                affectedPeople: body.affectedPeople,
                assistanceRequested: body.assistanceRequested,
                verificationStatus: "PENDING",
                missionStatus: "UNASSIGNED",
                createdAt: now,
                updatedAt: now,
                attachmentUrl: body.attachmentUrl.trim(),
                attachmentName: body.attachmentName.trim(),
                contactInfo: body.contactInfo.trim(),
                completionOutcome: "",
                history: [{actor: actor.username, action: "Incident reported", createdAt: now}]
            };
            incidents[id] = incident;
            var saved = persistIncidentsToFile();
            if saved is error {
                _ = incidents.remove(id);
                return saved;
            }
            notifyIncident("team", "New incident awaiting review", "A new report has been submitted: " + id + ". Review it in RescuePulse.");
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
            if actor.role == "user" && previous.originRole == "citizen" {
                return <http:Forbidden>{body: {message: "Responder changes to community reports must use mission updates or field notes"}};
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
            if changes.contactInfo is string {
                updated.contactInfo = (<string>changes.contactInfo).trim();
            }
            if changes.completionOutcome is string {
                updated.completionOutcome = (<string>changes.completionOutcome).trim();
            }
            if updated.status == "CLOSED" {
                updated.status = "RESOLVED";
                updated.missionStatus = "CLOSED";
            }
            if updated.assignee != previous.assignee {
                if previous.assignee != "" && updated.assignee != "" {
                    updated.missionStatus = "ASSIGNED";
                } else if updated.assignee == "" {
                    updated.missionStatus = "UNASSIGNED";
                } else {
                    updated.missionStatus = "ASSIGNED";
                }
            }
            if !validIncident(updated) || !validCategory(updated.category) || !validDeadline(updated.dueAt) || (updated.assignee != "" && !users.hasKey(updated.assignee)) {
                return <http:BadRequest>{body: {message: "Invalid incident details, assignee or response deadline"}};
            }
            User? reporter = users[previous.reportedBy];
            if reporter is User && reporter.role == "citizen" && previous.verificationStatus != "VERIFIED" &&
                ((updated.assignee != "" && updated.assignee != previous.assignee) || updated.status != previous.status) {
                return <http:BadRequest>{body: {message: "Verify a community report before dispatch or mission status changes"}};
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
            if updated.assignee != previous.assignee && updated.assignee != "" {
                notifyIncident(updated.assignee, "New rescue assignment", "Mission " + updated.id + " has been assigned to you. Review it in RescuePulse.");
            }
            return updated;

        }
    }

    // New verified dispatch workflow. Legacy PATCH remains available for old clients.
    resource function post [string id]/verify(http:Request req, @http:Payload VerificationRequest body) returns Incident|http:Unauthorized|http:Forbidden|http:BadRequest|http:NotFound|http:Conflict|error {
        lock {
            User? actor = currentUser(req);
            if actor is () { return <http:Unauthorized>{body: {message: "Please sign in"}}; }
            if actor.role != "admin" { return <http:Forbidden>{body: {message: "Coordinator access required"}}; }
            var previous = incidents[id];
            if previous is () { return <http:NotFound>{body: {message: "Incident not found"}}; }
            if body.revision != previous.revision { return <http:Conflict>{body: {message: "Refresh the incident before verifying"}}; }
            if previous.verificationStatus != "PENDING" || previous.archived || previous.status == "RESOLVED" {
                return <http:BadRequest>{body: {message: "Only pending active reports may be reviewed"}};
            }
            if body.decision != "VERIFIED" && body.decision != "REJECTED" {
                return <http:BadRequest>{body: {message: "Decision must be VERIFIED or REJECTED"}};
            }
            if body.decision == "REJECTED" && (body.reason.trim().length() < 5 || body.reason.length() > 500) {
                return <http:BadRequest>{body: {message: "Rejection needs a reason (5-500 characters)"}};
            }
            Incident updated = previous.clone();
            updated.verificationStatus = body.decision;
            updated.verificationReason = body.reason.trim();
            string now = time:utcToString(time:utcNow());
            updated.updatedAt = now; updated.revision += 1;
            updated.history.push({actor: actor.username, action: "Report " + body.decision + (body.reason == "" ? "" : ": " + body.reason.trim()), createdAt: now});
            check saveIncidentChange(previous, updated);
            notifyIncident(updated.reportedBy, "Incident review updated", "Report " + id + " review: " + body.decision);
            return updated;
        }
    }

    resource function post [string id]/mission(http:Request req, @http:Payload MissionRequest body) returns Incident|http:Unauthorized|http:Forbidden|http:BadRequest|http:NotFound|http:Conflict|error {
        lock {
            User? actor = currentUser(req);
            if actor is () { return <http:Unauthorized>{body: {message: "Please sign in"}}; }
            var previous = incidents[id];
            if previous is () { return <http:NotFound>{body: {message: "Incident not found"}}; }
            if body.revision != previous.revision { return <http:Conflict>{body: {message: "Mission changed. Refresh and try again"}}; }
            if previous.archived {
                return <http:BadRequest>{body: {message: "Cannot progress an archived incident"}};
            }

            boolean isResponder = actor.role == "user" && previous.assignee == actor.username;
            boolean isCoord = actor.role == "admin";

            if !isResponder && !isCoord {
                return <http:Forbidden>{body: {message: "Only the assigned responder or coordinator can update this mission"}};
            }

            string next = "";
            string historyAction = "";

            if isResponder {
                if previous.assignee == "" || previous.verificationStatus != "VERIFIED" {
                    return <http:BadRequest>{body: {message: "A verified, assigned and active incident is required"}};
                }
                if body.action == "ACCEPT" && previous.missionStatus == "ASSIGNED" {
                    next = "ACCEPTED";
                    historyAction = "Mission accepted";
                } else if body.action == "DECLINE" && previous.missionStatus == "ASSIGNED" {
                    next = "DECLINED";
                    historyAction = "Mission assignment declined";
                } else if body.action == "EN_ROUTE" && previous.missionStatus == "ACCEPTED" {
                    next = "EN_ROUTE";
                    historyAction = "Mission en route";
                } else if body.action == "ON_SCENE" && previous.missionStatus == "EN_ROUTE" {
                    next = "ON_SCENE";
                    historyAction = "Mission on scene";
                } else if body.action == "COMPLETE" && previous.missionStatus == "ON_SCENE" {
                    next = "COMPLETED";
                    historyAction = "Mission completed" + (body.outcome.trim() != "" ? ": " + body.outcome.trim() : "");
                }
            } else if isCoord {
                if body.action == "CANCEL" && (previous.missionStatus == "ASSIGNED" || previous.missionStatus == "ACCEPTED" || previous.missionStatus == "EN_ROUTE" || previous.missionStatus == "ON_SCENE") {
                    next = "CANCELLED";
                    historyAction = "Mission cancelled by coordinator";
                } else if body.action == "CLOSE" && (previous.missionStatus == "COMPLETED" || previous.status == "RESOLVED") {
                    next = "CLOSED";
                    historyAction = "Incident closed and verified by coordinator";
                }
            }

            if next == "" {
                return <http:BadRequest>{body: {message: "Invalid mission transition: " + body.action + " from " + previous.missionStatus}};
            }

            Incident updated = previous.clone();
            updated.missionStatus = next;
            if next == "ACCEPTED" { updated.status = "ACK"; }
            if next == "COMPLETED" {
                updated.status = "RESOLVED";
                if body.outcome.trim().length() > 0 {
                    updated.completionOutcome = body.outcome.trim();
                    string noteId = uuid:createType4AsString();
                    string nowStr = time:utcToString(time:utcNow());
                    updated.notes.push({id: noteId, author: actor.username, text: "[Completion Report] " + body.outcome.trim(), createdAt: nowStr});
                }
            }
            if next == "DECLINED" || next == "CANCELLED" {
                updated.assignee = "";
                updated.missionStatus = "UNASSIGNED";
            }
            if next == "CLOSED" {
                updated.status = "RESOLVED";
            }
            string now = time:utcToString(time:utcNow());
            updated.updatedAt = now; updated.revision += 1;
            updated.history.push({actor: actor.username, action: historyAction, createdAt: now});
            check saveIncidentChange(previous, updated);
            notifyIncident(updated.reportedBy, "Rescue mission update", "Report " + id + " mission: " + next);
            notifyIncident("team", "Mission status updated", "Report " + id + " mission: " + next);
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
                if actor.role == "citizen" {
                    Incident limited = incident.clone();
                    limited.notes = [];
                    limited.history = [];
                    limited.assignee = "";
                    limited.dueAt = "";
                    return limited;
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
                    if actor.role == "citizen" {
                        Incident limited = incident.clone();
                        limited.notes = [];
                        limited.history = [];
                        limited.assignee = "";
                        limited.dueAt = "";
                        out.push(limited);
                    } else {
                        out.push(incident);
                    }
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

    resource function post upload(http:Request req, @http:Payload AttachmentUploadRequest body) returns json|http:Unauthorized|http:BadRequest|error {
        lock {
            User? actor = currentUser(req);
            if actor is () { return <http:Unauthorized>{body: {message: "Please sign in"}}; }
            string? ext = validImageExtension(body.filename);
            if ext is () || !validMimeType(body.mimeType) {
                return <http:BadRequest>{body: {message: "Only JPG, PNG, and WebP images are permitted"}};
            }
            string cleanData = body.base64Data;
            int? commaIdx = cleanData.indexOf(",");
            if commaIdx is int {
                cleanData = cleanData.substring(commaIdx + 1);
            }
            byte[]|error fileBytes = array:fromBase64(cleanData);
            if fileBytes is error {
                return <http:BadRequest>{body: {message: "Invalid image encoding"}};
            }
            if fileBytes.length() == 0 || fileBytes.length() > 5 * 1024 * 1024 {
                return <http:BadRequest>{body: {message: "Image size must be between 1 byte and 5 MB"}};
            }
            if ext == ".jpg" {
                if fileBytes.length() < 3 || fileBytes[0] != 0xFF || fileBytes[1] != 0xD8 || fileBytes[2] != 0xFF {
                    return <http:BadRequest>{body: {message: "File content does not match JPEG format"}};
                }
            } else if ext == ".png" {
                if fileBytes.length() < 4 || fileBytes[0] != 0x89 || fileBytes[1] != 0x50 || fileBytes[2] != 0x4E || fileBytes[3] != 0x47 {
                    return <http:BadRequest>{body: {message: "File content does not match PNG format"}};
                }
            }
            string safeFilename = "att-" + uuid:createType4AsString() + ext;
            string filePath = dataDir + "/attachments/" + safeFilename;
            check io:fileWriteBytes(filePath, fileBytes);
            return {
                status: "ok",
                filename: safeFilename,
                originalName: body.filename,
                url: "/incident/attachment/" + safeFilename
            };
        }
    }

    resource function get attachment/[string filename](http:Request req) returns http:Response|http:Unauthorized|http:Forbidden|http:NotFound|error {
        lock {
            User? actor = currentUser(req);
            if actor is () { return <http:Unauthorized>{body: {message: "Please sign in"}}; }
            if filename.includes("..") || filename.includes("/") || filename.includes("\\") || filename.includes(":") || !filename.startsWith("att-") {
                return <http:NotFound>{body: {message: "Attachment not found"}};
            }
            string? ext = validImageExtension(filename);
            if ext is () { return <http:NotFound>{body: {message: "Attachment not found"}}; }

            if actor.role != "admin" {
                boolean hasAccess = false;
                foreach var inc in incidents {
                    if inc.attachmentUrl.endsWith(filename) {
                        if actor.role == "user" && (inc.assignee == actor.username || inc.reportedBy == actor.username) {
                            hasAccess = true;
                            break;
                        }
                        if actor.role == "citizen" && inc.reportedBy == actor.username {
                            hasAccess = true;
                            break;
                        }
                    }
                }
                if !hasAccess {
                    return <http:Forbidden>{body: {message: "You do not have permission to view this attachment"}};
                }
            }

            string filePath = dataDir + "/attachments/" + filename;
            if !(check file:test(filePath, file:EXISTS)) {
                return <http:NotFound>{body: {message: "Attachment not found"}};
            }
            byte[] fileBytes = check io:fileReadBytes(filePath);
            http:Response res = new;
            res.setPayload(fileBytes);
            string contentType = ext == ".png" ? "image/png" : ext == ".webp" ? "image/webp" : "image/jpeg";
            res.setHeader("content-type", contentType);
            res.setHeader("x-content-type-options", "nosniff");
            res.setHeader("cache-control", "private, max-age=86400");
            return res;
        }
    }
}

function validIncident(Incident inc) returns boolean {
    boolean haveLat = inc.latitude is float;
    boolean haveLon = inc.longitude is float;
    if haveLat != haveLon { return false; }
    if inc.latitude is float && (inc.latitude < -90.0 || inc.latitude > 90.0) { return false; }
    if inc.longitude is float && (inc.longitude < -180.0 || inc.longitude > 180.0) { return false; }
    if inc.affectedPeople < 0 || inc.affectedPeople > 1000000 { return false; }
    return inc.location.trim().length() > 0 && inc.location.length() <= 100 &&
        inc.description.trim().length() > 0 && inc.description.length() <= 2000 &&
        !inc.location.includes("\t") && !inc.location.includes("\n") && !inc.location.includes("\r") &&
        (inc.severity == "LOW" || inc.severity == "MEDIUM" || inc.severity == "HIGH" || inc.severity == "CRITICAL") &&
        (inc.status == "OPEN" || inc.status == "ACK" || inc.status == "RESOLVED" || inc.status == "CLOSED");
}
