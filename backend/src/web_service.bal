import ballerina/http;
import ballerina/io;

service / on httpListener {
    resource function get .() returns http:Response|http:NotFound|error {
        return serveFile(["index.html"]);
    }

    resource function get [string... p]() returns http:Response|http:NotFound|error {
        if p.length() == 0 {
            return serveFile(["index.html"]);
        }
        // Prevent path traversal
        foreach var seg in p {
            if seg.includes("..") || seg.includes("\\") || seg.includes(":") {
                return {body: {message: "not found"}};
            }
        }
        return serveFile(p);
    }
}

function serveFile(string[] segments) returns http:Response|http:NotFound|error {
    string joined = joinPath(segments);
    string[] candidates = [
        "frontend/" + joined,
        "../frontend/" + joined,
        "../../frontend/" + joined
    ];
    byte[]|error content = error("not found");
    string chosenPath = "";
    foreach var p in candidates {
        var r = io:fileReadBytes(p);
        if r is byte[] {
            content = r;
            chosenPath = p;
            break;
        }
    }
    if content is error {
        return {body: {message: "not found"}};
    }
    http:Response res = new;
    res.setPayload(<byte[]>content);
    res.setHeader("content-type", resolveContentType(chosenPath));
    return res;
}

function joinPath(string[] segments) returns string {
    if segments.length() == 0 {
        return "";
    }
    string out = segments[0];
    foreach int i in 1 ..< (segments.length()) {
        out = out + "/" + segments[i];
    }
    return out;
}

function resolveContentType(string path) returns string {
    if path.endsWith(".html") {
        return "text/html; charset=utf-8";
    }
    if path.endsWith(".css") {
        return "text/css";
    }
    if path.endsWith(".js") {
        return "application/javascript";
    }
    if path.endsWith(".png") {
        return "image/png";
    }
    if path.endsWith(".jpg") || path.endsWith(".jpeg") {
        return "image/jpeg";
    }
    if path.endsWith(".svg") {
        return "image/svg+xml";
    }
    if path.endsWith(".ico") {
        return "image/x-icon";
    }
    if path.endsWith(".webmanifest") || path.endsWith(".json") {
        return "application/json";
    }
    return "application/octet-stream";
}

