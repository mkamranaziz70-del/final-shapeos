enum AgentRole { user, assistant, system, tool }

/// One turn in the agent conversation.
class AgentMessage {
  final AgentRole role;
  final String content;
  final DateTime timestamp;

  const AgentMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  factory AgentMessage.user(String text) => AgentMessage(
        role: AgentRole.user,
        content: text,
        timestamp: DateTime.now(),
      );

  factory AgentMessage.assistant(String text) => AgentMessage(
        role: AgentRole.assistant,
        content: text,
        timestamp: DateTime.now(),
      );

  factory AgentMessage.system(String text) => AgentMessage(
        role: AgentRole.system,
        content: text,
        timestamp: DateTime.now(),
      );

  factory AgentMessage.tool(String text) => AgentMessage(
        role: AgentRole.tool,
        content: text,
        timestamp: DateTime.now(),
      );
}

/// A persisted record of an action the agent took on the
/// home, with the natural-language reason. The agent reads
/// these back when answering "why did you …" questions.
class AgentAction {
  final String id;
  final String deviceId;
  final String deviceName;
  final String action;
  final String reason;
  final String trigger;
  final DateTime timestamp;

  const AgentAction({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.action,
    required this.reason,
    required this.trigger,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
        "deviceId": deviceId,
        "deviceName": deviceName,
        "action": action,
        "reason": reason,
        "trigger": trigger,
        "timestamp": timestamp.toIso8601String(),
        "epoch": timestamp.millisecondsSinceEpoch,
      };

  factory AgentAction.fromMap(String id, Map<String, dynamic> m) =>
      AgentAction(
        id: id,
        deviceId: m["deviceId"]?.toString() ?? "",
        deviceName: m["deviceName"]?.toString() ?? "",
        action: m["action"]?.toString() ?? "",
        reason: m["reason"]?.toString() ?? "",
        trigger: m["trigger"]?.toString() ?? "",
        timestamp: DateTime.tryParse(m["timestamp"]?.toString() ?? "") ??
            DateTime.now(),
      );
}
