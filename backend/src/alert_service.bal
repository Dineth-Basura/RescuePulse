import ballerina/http;
import ballerina/io;
import ballerina/log;

type EvaluateRequest record {
    float riskScore;
    float threshold?;
    string channel?;
    string target?;
};

type AlertResponse record {
    string status;
    string message?;
};

final float DEFAULT_ALERT_THRESHOLD = 0.65;

service /alert on httpListener {
    resource function get health() returns json {
        return {status: "alert-service:ok"};
    }

    resource function post evaluate(@http:Payload EvaluateRequest body) returns AlertResponse|http:BadRequest {
        float risk = body.riskScore;
        float threshold = body.threshold ?: DEFAULT_ALERT_THRESHOLD;
        if risk < 0.0 || risk > 1.0 || threshold < 0.0 || threshold > 1.0 {
            return <http:BadRequest>{body: {message: "Risk and threshold must be between 0 and 1"}};
        }
        if risk >= threshold {
            string ch = body.channel ?: "console";
            string tgt = body.target ?: "anonymous";
            log:printInfo("ALERT triggered (risk=" + risk.toString() + ") to " + tgt);
            if ch == "console" {
                io:println("[ALERT] risk score " + risk.toString() + " for target " + tgt);
            }
            return {status: "alerted", message: "Simulated alert only; no external delivery"};
        }
        return {status: "ok", message: "below threshold"};
    }
}

