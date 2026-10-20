import ballerina/file;
import ballerina/http;
import ballerina/io;
import ballerina/log;

type WeatherRecord record {|
    float rainMm;
    float windKph;
    float tempC;
    float humidityPct;
    float soilSatPct;
    string location;
    string timestamp;
|};

WeatherRecord[] weatherData = [];

final string WEATHER_PATH = dataDir + "/weather.json";

function loadWeather() returns error? {
    if check file:test(WEATHER_PATH, file:EXISTS) {
        json saved = check io:fileReadJson(WEATHER_PATH);
        weatherData = check saved.cloneWithType();
    }
}

function saveWeather() returns error? {
    check io:fileWriteJson(WEATHER_PATH, weatherData);
}

service /data on httpListener {
    resource function get health() returns json {
        return {status: "data-service:ok"};
    }

    resource function post ingest(http:Request req, @http:Payload WeatherRecord rec) returns json|http:BadRequest|http:Unauthorized|error {
        if currentUser(req) is () {
            return <http:Unauthorized>{body: {message: "Please sign in"}};
        }
        WeatherRecord[] previous = weatherData.clone();
        if !validWeather(rec.rainMm, rec.windKph, rec.tempC, rec.humidityPct, rec.soilSatPct) || rec.location.trim().length() == 0 || rec.location.length() > 100 || rec.timestamp.length() > 50 {
            return <http:BadRequest>{body: {message: "Invalid weather record"}};
        }
        lock {
            weatherData.push(rec);
            if weatherData.length() > 1000 {
                _ = weatherData.remove(0);
            }
        }
        var saved = saveWeather();
        if saved is error {
            weatherData = previous;
            return saved;
        }
        log:printInfo("Ingested record for " + rec.location + " at " + rec.timestamp);
        return {status: "stored"};
    }

    resource function get latest/[string location](http:Request req) returns WeatherRecord[]|json|http:Unauthorized {
        if currentUser(req) is () {
            return <http:Unauthorized>{body: {message: "Please sign in"}};
        }
        WeatherRecord[] out = [];
        foreach var r in weatherData {
            if r.location == location {
                out.push(r);
            }
        }
        if out.length() == 0 {
            return {message: "no data"};
        }
        return out;
    }

    resource function post ingestBatch(http:Request req, @http:Payload WeatherRecord[] recs) returns json|http:BadRequest|http:Unauthorized|error {
        if currentUser(req) is () {
            return <http:Unauthorized>{body: {message: "Please sign in"}};
        }
        WeatherRecord[] previous = weatherData.clone();
        if recs.length() > 100 {
            return <http:BadRequest>{body: {message: "Maximum 100 records per batch"}};
        }
        foreach var rec in recs {
            if !validWeather(rec.rainMm, rec.windKph, rec.tempC, rec.humidityPct, rec.soilSatPct) || rec.location.trim().length() == 0 || rec.location.length() > 100 || rec.timestamp.length() > 50 {
                return <http:BadRequest>{body: {message: "Invalid weather record"}};
            }
        }
        int n = 0;
        lock {
            foreach var r in recs {
                weatherData.push(r);
                n += 1;
                if weatherData.length() > 1000 {
                    _ = weatherData.remove(0);
                }
            }
        }
        var saved = saveWeather();
        if saved is error {
            weatherData = previous;
            return saved;
        }
        log:printInfo("Batch ingested records count=" + n.toString());
        return {status: "stored", count: n};
    }

    resource function get locations(http:Request req) returns json|http:Unauthorized {
        if currentUser(req) is () {
            return <http:Unauthorized>{body: {message: "Please sign in"}};
        }
        map<boolean> seen = {};
        string[] out = [];
        foreach var r in weatherData {
            if !seen.hasKey(r.location) {
                seen[r.location] = true;
                out.push(r.location);
            }
        }
        return {locations: out};
    }

    resource function get all(http:Request req) returns WeatherRecord[]|json|http:Unauthorized {
        if currentUser(req) is () {
            return <http:Unauthorized>{body: {message: "Please sign in"}};
        }
        if weatherData.length() == 0 {
            return {message: "no data"};
        }
        return weatherData;
    }

    resource function get stats(http:Request req) returns json|http:Unauthorized {
        if currentUser(req) is () {
            return <http:Unauthorized>{body: {message: "Please sign in"}};
        }
        int n = weatherData.length();
        if n == 0 {
            return {count: 0};
        }
        float sumRain = 0.0;
        float sumWind = 0.0;
        float sumTemp = 0.0;
        float sumHum = 0.0;
        float sumSoil = 0.0;
        foreach var r in weatherData {
            sumRain += r.rainMm;
            sumWind += r.windKph;
            sumTemp += r.tempC;
            sumHum += r.humidityPct;
            sumSoil += r.soilSatPct;
        }
        return {
            count: n,
            avgRainMm: sumRain / n,
            avgWindKph: sumWind / n,
            avgTempC: sumTemp / n,
            avgHumidityPct: sumHum / n,
            avgSoilSatPct: sumSoil / n
        };
    }
}

