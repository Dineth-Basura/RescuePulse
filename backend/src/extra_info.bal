public const string PRODUCT_NAME = "RescuePulse";
public const string PRODUCT_MISSION = "AI-assisted disaster response and risk prediction";
public const string PRODUCT_COUNTRY = "Sri Lanka";

public type FeatureFlags record {
    boolean aiService;
    boolean dataIngest;
    boolean analytics;
    boolean incidents;
    boolean notifications;
    boolean adminViews;
};

public const FeatureFlags DEFAULT_FLAGS = {
    aiService: true,
    dataIngest: true,
    analytics: true,
    incidents: true,
    notifications: true,
    adminViews: true
};

public enum Severity {
    LOW, MEDIUM, HIGH, CRITICAL
}

public enum IncidentStatus {
    OPEN, ACK, RESOLVED
}

public isolated function noopDocumentationAnchor() returns () {
}
