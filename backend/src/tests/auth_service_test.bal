import ballerina/http;
import ballerina/test;
import ballerina/uuid;

@test:Config {}
function testSignupLogin() returns error? {
    string username = "test-" + uuid:createType4AsString().substring(0, 12);
    http:Client c = check new ("http://localhost:8080");
    json s = check c->post("/auth/signup", {username: username, password: "pass1234"}, targetType = json);
    test:assertEquals(s.status, "ok");
    json l = check c->post("/auth/login", {username: username, password: "pass1234"}, targetType = json);
    test:assertEquals(l.status, "ok");
    test:assertTrue(l.token is string);
}

