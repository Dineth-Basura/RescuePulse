import ballerina/http;
import ballerina/test;
import ballerina/uuid;

type NotificationList Notification[];

@test:Config {}
function testOperationalPermissionsAndLifecycle() returns error? {
    http:Client c = check new ("http://localhost:8080");
    string username = "ops-" + uuid:createType4AsString().substring(0, 12);
    AuthResponse signup = check c->post("/auth/signup", {username, password: "Operations-test-2026"}, targetType = AuthResponse);
    test:assertEquals(signup.status, "ok");
    AuthResponse login = check c->post("/auth/login", {username, password: "Operations-test-2026"}, targetType = AuthResponse);
    map<string> responder = {Authorization: "Bearer " + (login.token ?: "")};
    AuthResponse adminLogin = check c->post("/auth/login", {username: "admin", password: "Test-only-password-2026"}, targetType = AuthResponse);
    map<string> coordinator = {Authorization: "Bearer " + (adminLogin.token ?: "")};
    Incident report = check c->post("/incident/create", {location: "Ratnapura", description: "Water level rising near access road", severity: "HIGH", category: "FLOOD"}, headers = responder, targetType = Incident);
    test:assertEquals(report.reportedBy, username);
    test:assertEquals(report.history.length(), 1);
    http:Response unauthorizedUpdate = check c->patch("/incident/" + report.id, {revision: report.revision, status: "ACK"}, headers = responder);
    test:assertEquals(unauthorizedUpdate.statusCode, 403);
    Incident assigned = check c->patch("/incident/" + report.id, {revision: report.revision, assignee: username, dueAt: "2030-01-01T12:00:00Z"}, headers = coordinator, targetType = Incident);
    test:assertEquals(assigned.assignee, username);
    http:Response staleUpdate = check c->patch("/incident/" + report.id, {revision: report.revision, severity: "LOW"}, headers = coordinator);
    test:assertEquals(staleUpdate.statusCode, 409);
    Incident acknowledged = check c->patch("/incident/" + report.id, {revision: assigned.revision, status: "ACK"}, headers = responder, targetType = Incident);
    test:assertEquals(acknowledged.status, "ACK");
    http:Response deniedAssignment = check c->patch("/incident/" + report.id, {revision: acknowledged.revision, assignee: "admin"}, headers = responder);
    test:assertEquals(deniedAssignment.statusCode, 403);
    Incident noted = check c->post("/incident/" + report.id + "/notes", {text: "Access road checked; team proceeding on foot"}, headers = responder, targetType = Incident);
    test:assertEquals(noted.notes.length(), 1);
    test:assertEquals(noted.notes[0].author, username);
    http:Response deniedArchive = check c->patch("/incident/" + report.id, {revision: noted.revision, archived: true}, headers = coordinator);
    test:assertEquals(deniedArchive.statusCode, 400);
    Incident resolved = check c->patch("/incident/" + report.id, {revision: noted.revision, status: "RESOLVED"}, headers = responder, targetType = Incident);
    Incident archived = check c->patch("/incident/" + report.id, {revision: resolved.revision, archived: true}, headers = coordinator, targetType = Incident);
    test:assertTrue(archived.archived);
    Incident restored = check c->patch("/incident/" + report.id, {revision: archived.revision, archived: false}, headers = coordinator, targetType = Incident);
    test:assertFalse(restored.archived);
    test:assertTrue(restored.history.length() >= 6);
    http:Response deniedBroadcast = check c->post("/notify/publish", {title: "Unauthorized broadcast", body: "Should not be sent", target: "team"}, headers = responder);
    test:assertEquals(deniedBroadcast.statusCode, 403);
    Notification notice = check c->post("/notify/publish", {title: "Response update", body: "Review your assigned incident", target: username}, headers = coordinator, targetType = Notification);
    http:Response marked = check c->put("/notify/read/" + notice.id, {}, headers = responder);
    test:assertEquals(marked.statusCode, 200);
    Notification[] feed = check c->get("/notify/list", headers = responder, targetType = NotificationList);
    boolean foundRead = false;
    foreach var item in feed {
        if item.id == notice.id && item.readBy.indexOf(username) is int {
            foundRead = true;
        }
    }
    test:assertTrue(foundRead);
    http:Response invalidRole = check c->put("/admin/users/" + username + "/role", {role: "admin"}, headers = responder);
    test:assertEquals(invalidRole.statusCode, 403);
    http:Response wrongPassword = check c->put("/auth/password", {currentPassword: "wrong", newPassword: "New-operations-test-2026"}, headers = responder);
    test:assertEquals(wrongPassword.statusCode, 400);
    http:Response passwordChanged = check c->put("/auth/password", {currentPassword: "Operations-test-2026", newPassword: "New-operations-test-2026"}, headers = responder);
    test:assertEquals(passwordChanged.statusCode, 200);
    http:Response revoked = check c->get("/auth/me", headers = responder);
    test:assertEquals(revoked.statusCode, 401);
    AuthResponse relogin = check c->post("/auth/login", {username, password: "New-operations-test-2026"}, targetType = AuthResponse);
    test:assertEquals(relogin.status, "ok");
    http:Response removed = check c->delete("/incident/" + report.id, headers = coordinator);
    test:assertEquals(removed.statusCode, 200);
}
