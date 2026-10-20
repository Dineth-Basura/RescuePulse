import ballerina/http;
import ballerina/io;
import ballerina/file;
import ballerina/time;
import ballerina/uuid;
import ballerina/crypto;
import ballerina/log;

type RoleChange record {| string role; |};
type AccountStatusChange record {| boolean enabled; |};
type AdminCreateUser record {| string username; string password; string role = "user"; |};
type WorkspacePolicy record {|
    boolean registrationOpen = true;
    boolean aiEnabled = true;
    int aiHourlyLimit = 60;
    int revision = 1;
|};
type AdminAudit record {| string id; string actor; string action; string target; string details; string createdAt; |};
type AdminState record {| WorkspacePolicy policy = {}; AdminAudit[] audit = []; |};
AdminState adminState = {};
final string ADMIN_STATE_PATH = dataDir + "/administration.json";

function loadAdminState() returns error? {
    adminState.policy.aiHourlyLimit = geminiMaxRequestsPerHour;
    if check file:test(ADMIN_STATE_PATH, file:EXISTS) {
        json saved = check io:fileReadJson(ADMIN_STATE_PATH);
        adminState = check saved.cloneWithType();
    }
}
function saveAdminState() returns error? { check io:fileWriteJson(ADMIN_STATE_PATH, adminState); }
function auditAdmin(string actor, string action, string target, string details) returns boolean {
    AdminAudit[] previous = adminState.audit.clone();
    adminState.audit.push({id: uuid:createType4AsString(), actor, action, target, details, createdAt: time:utcToString(time:utcNow())});
    if adminState.audit.length() > 1000 { _ = adminState.audit.remove(0); }
    if saveAdminState() is error {
        adminState.audit = previous;
        log:printError("An administrative action completed but its audit record could not be persisted");
        return false;
    }
    return true;
}
function activeSessionCount(string username) returns int {
    int count = 0;
    foreach var session in sessions { if session.username == username && session.expires > time:utcNow()[0] { count += 1; } }
    return count;
}
function revokeUserSessions(string username) returns int {
    int count = 0;
    foreach string token in sessions.keys() {
        var session = sessions[token];
        if session is Session && session.username == username { _ = sessions.remove(token); count += 1; }
    }
    return count;
}
function adminIncidentOverdue(Incident incident) returns boolean {
    if incident.archived || incident.status == "RESOLVED" || incident.dueAt == "" { return false; }
    var deadline = time:utcFromString(incident.dueAt);
    return deadline is time:Utc && deadline[0] < time:utcNow()[0];
}

service /admin on httpListener {
    resource function get health() returns json { return {status: "admin-service:ok"}; }
    resource function get overview(http:Request req) returns json|http:Forbidden {
        lock {
            if !isAdmin(req) { return <http:Forbidden>{body: {message: "Administrator access required"}}; }
            int activeUsers = 0; int suspendedUsers = 0; int activeSessions = 0;
            foreach var user in users {
                if user.enabled { activeUsers += 1; } else { suspendedUsers += 1; }
                activeSessions += activeSessionCount(user.username);
            }
            int open = 0; int unassigned = 0; int overdue = 0; int critical = 0; int resolved = 0; int archived = 0;
            json[] workloads = [];
            foreach var incident in incidents {
                if incident.archived { archived += 1; continue; }
                if incident.status == "RESOLVED" { resolved += 1; continue; }
                open += 1;
                if incident.assignee == "" { unassigned += 1; }
                if adminIncidentOverdue(incident) { overdue += 1; }
                if incident.severity == "CRITICAL" || incident.severity == "HIGH" { critical += 1; }
            }
            foreach var user in users {
                int assigned = 0;
                foreach var incident in incidents { if !incident.archived && incident.status != "RESOLVED" && incident.assignee == user.username { assigned += 1; } }
                workloads.push({username: user.username, enabled: user.enabled, role: user.role, assigned});
            }
            return {activeUsers, suspendedUsers, activeSessions, openIncidents: open, unassignedIncidents: unassigned,
                overdueIncidents: overdue, highPriorityIncidents: critical, resolvedIncidents: resolved, archivedIncidents: archived, workloads};
        }
    }
    resource function get users(http:Request req) returns json|http:Forbidden {
        lock {
            if !isAdmin(req) { return <http:Forbidden>{body: {message: "Administrator access required"}}; }
            json[] out = [];
            foreach var user in users { out.push({username: user.username, role: user.role, enabled: user.enabled,
                createdAt: user.createdAt, lastLogin: user.lastLogin, activeSessions: activeSessionCount(user.username)}); }
            return {users: out};
        }
    }
    resource function post users(http:Request req, @http:Payload AdminCreateUser body) returns json|http:Forbidden|http:BadRequest|http:Conflict|error {
        lock {
            User? actor = currentUser(req);
            if actor is () || actor.role != "admin" { return <http:Forbidden>{body: {message: "Administrator access required"}}; }
            string username = body.username.trim().toLowerAscii();
            if !validUsername(username) || username == "admin" || body.password.length() < 8 || body.password.toBytes().length() > 72 || (body.role != "user" && body.role != "admin") {
                return <http:BadRequest>{body: {message: "Use a valid username, role and an 8-72 byte password"}};
            }
            if users.hasKey(username) { return <http:Conflict>{body: {message: "Username already exists"}}; }
            users[username] = {username, password: check crypto:hashBcrypt(body.password), role: body.role, createdAt: time:utcToString(time:utcNow())};
            var saved = saveUsers();
            if saved is error { _ = users.remove(username); return saved; }
            boolean auditRecorded = auditAdmin(actor.username, "ACCOUNT_CREATED", username, "Role: " + body.role);
            return {status: "ok", username, auditRecorded};
        }
    }
    resource function put users/[string username]/role(http:Request req, @http:Payload RoleChange body) returns json|http:Forbidden|http:BadRequest|http:NotFound|error {
        lock {
            User? actor = currentUser(req);
            if actor is () || actor.role != "admin" { return <http:Forbidden>{body: {message: "Administrator access required"}}; }
            if body.role != "admin" && body.role != "user" { return <http:BadRequest>{body: {message: "Choose a valid account role"}}; }
            if username == actor.username || username == "admin" { return <http:BadRequest>{body: {message: "Your own role and the primary administrator role are protected"}}; }
            var previous = users[username];
            if previous is () { return <http:NotFound>{body: {message: "Account not found"}}; }
            User updated = previous.clone(); updated.role = body.role; users[username] = updated;
            var saved = saveUsers(); if saved is error { users[username] = previous; return saved; }
            boolean auditRecorded = auditAdmin(actor.username, "ROLE_CHANGED", username, previous.role + " to " + body.role);
            return {status: "ok", username, role: updated.role, auditRecorded};
        }
    }
    resource function put users/[string username]/status(http:Request req, @http:Payload AccountStatusChange body) returns json|http:Forbidden|http:BadRequest|http:NotFound|error {
        lock {
            User? actor = currentUser(req);
            if actor is () || actor.role != "admin" { return <http:Forbidden>{body: {message: "Administrator access required"}}; }
            if username == actor.username || username == "admin" { return <http:BadRequest>{body: {message: "Your own account and the primary administrator are protected"}}; }
            var previous = users[username];
            if previous is () { return <http:NotFound>{body: {message: "Account not found"}}; }
            User updated = previous.clone(); updated.enabled = body.enabled; users[username] = updated;
            var saved = saveUsers(); if saved is error { users[username] = previous; return saved; }
            if !body.enabled { _ = revokeUserSessions(username); }
            boolean auditRecorded = auditAdmin(actor.username, body.enabled ? "ACCOUNT_ENABLED" : "ACCOUNT_SUSPENDED", username, "Account access changed");
            return {status: "ok", username, enabled: body.enabled, auditRecorded};
        }
    }
    resource function post users/[string username]/revoke(http:Request req) returns json|http:Forbidden|http:BadRequest|http:NotFound {
        lock {
            User? actor = currentUser(req);
            if actor is () || actor.role != "admin" { return <http:Forbidden>{body: {message: "Administrator access required"}}; }
            if username == actor.username { return <http:BadRequest>{body: {message: "Use Sign out to end your own session"}}; }
            if !users.hasKey(username) { return <http:NotFound>{body: {message: "Account not found"}}; }
            int revoked = revokeUserSessions(username);
            boolean auditRecorded = auditAdmin(actor.username, "SESSIONS_REVOKED", username, revoked.toString() + " sessions ended");
            return {status: "ok", revoked, auditRecorded};
        }
    }
    resource function get settings(http:Request req) returns json|http:Forbidden {
        lock {
            if !isAdmin(req) { return <http:Forbidden>{body: {message: "Administrator access required"}}; }
            int used = time:utcNow()[0] - aiWindowStart >= 3600 ? 0 : aiWindowRequests;
            return {policy: adminState.policy, aiConfigured: geminiApiKey.trim().length() > 0, aiModel: geminiModel, aiRequestsThisHour: used};
        }
    }
    resource function put settings(http:Request req, @http:Payload WorkspacePolicy body) returns json|http:Forbidden|http:BadRequest|http:Conflict|error {
        lock {
            User? actor = currentUser(req);
            if actor is () || actor.role != "admin" { return <http:Forbidden>{body: {message: "Administrator access required"}}; }
            if body.revision != adminState.policy.revision { return <http:Conflict>{body: {message: "Settings changed. Refresh before saving."}}; }
            if body.aiHourlyLimit < 1 || body.aiHourlyLimit > 1000 { return <http:BadRequest>{body: {message: "AI request limit must be between 1 and 1000 per hour"}}; }
            WorkspacePolicy previous = adminState.policy.clone();
            adminState.policy = {registrationOpen: body.registrationOpen, aiEnabled: body.aiEnabled, aiHourlyLimit: body.aiHourlyLimit, revision: previous.revision + 1};
            var saved = saveAdminState(); if saved is error { adminState.policy = previous; return saved; }
            boolean auditRecorded = auditAdmin(actor.username, "POLICY_UPDATED", "workspace", "Registration: " + body.registrationOpen.toString() + "; AI: " + body.aiEnabled.toString() + "; hourly limit: " + body.aiHourlyLimit.toString());
            return {status: "ok", policy: adminState.policy, auditRecorded};
        }
    }
    resource function get audit(http:Request req) returns json|http:Forbidden {
        lock {
            if !isAdmin(req) { return <http:Forbidden>{body: {message: "Administrator access required"}}; }
            AdminAudit[] out = adminState.audit.clone();
            foreach var incident in incidents {
                foreach int index in 0..<incident.history.length() {
                    IncidentEvent event = incident.history[index];
                    out.push({id: incident.id + "-" + index.toString(), actor: event.actor, action: "INCIDENT_ACTIVITY", target: incident.id,
                        details: event.action, createdAt: event.createdAt});
                }
            }
            return {events: out};
        }
    }
}
