import Foundation

/// Source for the small files Pip installs into agents that use plugins instead of hook configs.
/// Each forwards Claude-shaped events to pip-bridge and never blocks or changes the agent.
enum AgentPlugins {
    static func header(_ agent: String) -> String {
        "Pip: shows \(agent) sessions in the MacBook notch. Installed by Pip; remove it from Pip Settings → Disconnect."
    }

    static func jsonString(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        let array = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }

    /// ~/.config/opencode/plugins/pip.js
    static func openCode(bridgePath: String) -> String {
        """
        // \(header("OpenCode"))
        import { spawn } from "node:child_process";

        const BRIDGE = \(jsonString(bridgePath));

        function send(payload) {
          try {
            const child = spawn(BRIDGE, ["opencode"], { stdio: ["pipe", "ignore", "ignore"] });
            child.on("error", () => {});
            child.stdin.on("error", () => {});
            child.stdin.end(JSON.stringify(payload));
          } catch {}
        }

        export const PipNotch = async ({ directory }) => {
          const base = (id) => ({ session_id: `opencode-${id ?? "main"}`, cwd: directory });
          return {
            event: async ({ event }) => {
              const p = event.properties ?? {};
              const id = p.sessionID ?? p.info?.id;
              switch (event.type) {
                case "session.created":
                  send({ ...base(id), hook_event_name: "SessionStart" });
                  break;
                case "session.deleted":
                  send({ ...base(id), hook_event_name: "SessionEnd" });
                  break;
                case "session.status":
                  if (p.status?.type === "busy") send({ ...base(id), hook_event_name: "AgentActive" });
                  break;
                case "session.idle":
                  send({ ...base(id), hook_event_name: "Stop" });
                  break;
                case "session.error":
                  send({
                    ...base(id),
                    hook_event_name: "StopFailure",
                    error: "error",
                    error_details: String(p.error?.data?.message ?? p.error?.name ?? "OpenCode hit an error"),
                  });
                  break;
                case "permission.asked":
                  send({ ...base(id), hook_event_name: "Notification", notification_type: "agent_needs_input" });
                  break;
                case "permission.replied":
                  send({ ...base(id), hook_event_name: "AgentActive" });
                  break;
              }
            },
            "tool.execute.before": async (input, output) => {
              send({ ...base(input.sessionID), hook_event_name: "PreToolUse", tool_name: input.tool, tool_input: output?.args ?? {} });
            },
          };
        };

        """
    }

    /// ~/.pi/agent/extensions/pip.ts
    static func pi(bridgePath: String) -> String {
        """
        // \(header("Pi"))
        import { spawn } from "node:child_process";

        const BRIDGE = \(jsonString(bridgePath));
        const SESSION = `pi-${process.pid}`;

        function send(payload: Record<string, unknown>) {
          try {
            const child = spawn(BRIDGE, ["pi"], { stdio: ["pipe", "ignore", "ignore"] });
            child.on("error", () => {});
            child.stdin?.on("error", () => {});
            child.stdin?.end(JSON.stringify({ session_id: SESSION, ...payload }));
          } catch {}
        }

        function lastAssistantText(messages: any[]): string | undefined {
          for (let i = messages.length - 1; i >= 0; i--) {
            const message = messages[i];
            if (message?.role !== "assistant") continue;
            if (typeof message.content === "string") return message.content;
            if (Array.isArray(message.content)) {
              const text = message.content.filter((part: any) => part?.type === "text").map((part: any) => part.text).join(" ");
              if (text) return text;
            }
          }
          return undefined;
        }

        export default function (pi: any) {
          let cwd = process.cwd();
          let reply: string | undefined;

          pi.on("session_start", async (_event: any, ctx: any) => {
            cwd = ctx?.cwd ?? cwd;
            send({ hook_event_name: "SessionStart", cwd });
          });
          pi.on("input", async (event: any, ctx: any) => {
            cwd = ctx?.cwd ?? cwd;
            send({ hook_event_name: "UserPromptSubmit", cwd, prompt: event?.text });
          });
          pi.on("agent_start", async () => {
            send({ hook_event_name: "AgentActive", cwd });
          });
          pi.on("tool_call", async (event: any) => {
            send({ hook_event_name: "PreToolUse", cwd, tool_name: event?.toolName, tool_input: event?.input ?? {} });
          });
          pi.on("agent_end", async (event: any) => {
            reply = lastAssistantText(event?.messages ?? []);
          });
          pi.on("agent_settled", async () => {
            send({ hook_event_name: "Stop", cwd, last_assistant_message: reply });
            reply = undefined;
          });
          pi.on("session_shutdown", async (event: any) => {
            if (event?.reason === "quit") send({ hook_event_name: "SessionEnd", cwd });
          });
        }

        """
    }

    /// ~/.ohmypi/extensions/pip.ts
    static func ohmypi(bridgePath: String) -> String {
        """
        // \(header("Oh My Pi"))
        import { spawn } from "node:child_process";

        const BRIDGE = \(jsonString(bridgePath));
        const SESSION = `ohmypi-${process.pid}`;

        function send(payload: Record<string, unknown>) {
          try {
            const child = spawn(BRIDGE, ["ohmypi"], { stdio: ["pipe", "ignore", "ignore"] });
            child.on("error", () => {});
            child.stdin?.on("error", () => {});
            child.stdin?.end(JSON.stringify({ session_id: SESSION, ...payload }));
          } catch {}
        }

        function lastAssistantText(messages: any[]): string | undefined {
          for (let i = messages.length - 1; i >= 0; i--) {
            const message = messages[i];
            if (message?.role !== "assistant") continue;
            if (typeof message.content === "string") return message.content;
            if (Array.isArray(message.content)) {
              const text = message.content.filter((part: any) => part?.type === "text").map((part: any) => part.text).join(" ");
              if (text) return text;
            }
          }
          return undefined;
        }

        export default function (pi: any) {
          let cwd = process.cwd();
          let reply: string | undefined;

          pi.on("session_start", async (_event: any, ctx: any) => {
            cwd = ctx?.cwd ?? cwd;
            send({ hook_event_name: "SessionStart", cwd });
          });
          pi.on("input", async (event: any, ctx: any) => {
            cwd = ctx?.cwd ?? cwd;
            send({ hook_event_name: "UserPromptSubmit", cwd, prompt: event?.text });
          });
          pi.on("agent_start", async () => {
            send({ hook_event_name: "AgentActive", cwd });
          });
          pi.on("tool_call", async (event: any) => {
            send({ hook_event_name: "PreToolUse", cwd, tool_name: event?.toolName, tool_input: event?.input ?? {} });
          });
          pi.on("agent_end", async (event: any) => {
            reply = lastAssistantText(event?.messages ?? []);
          });
          pi.on("agent_settled", async () => {
            send({ hook_event_name: "Stop", cwd, last_assistant_message: reply });
            reply = undefined;
          });
          pi.on("session_shutdown", async (event: any) => {
            if (event?.reason === "quit") send({ hook_event_name: "SessionEnd", cwd });
          });
        }

        """
    }

    /// ~/.copilot/hooks/pip.json. Copilot payloads don't name their event, so it's passed as an argument.
    static func copilot(bridgePath: String) -> String {
        let events = ["sessionStart", "sessionEnd", "userPromptSubmitted", "preToolUse", "postToolUse", "agentStop", "errorOccurred", "notification"]
        var hooks: [String: Any] = [:]
        for event in events {
            hooks[event] = [["type": "command", "bash": HookConfig.command(bridgePath: bridgePath, agent: .copilot, event: event), "timeoutSec": 5]]
        }
        let config: [String: Any] = ["version": 1, "hooks": hooks]
        let data = (try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// ~/.kiro/hooks/pip.json. Kiro's payload doesn't name its trigger, so it's passed as an argument.
    static func kiro(bridgePath: String) -> String {
        let hooks: [[String: Any]] = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"].map { (trigger: String) -> [String: Any] in
            [
                "name": "Pip notch: \(trigger)",
                "trigger": trigger,
                "action": ["type": "command", "command": HookConfig.command(bridgePath: bridgePath, agent: .kiro, event: trigger)],
                "timeout": 5,
                "enabled": true,
            ]
        }
        let config: [String: Any] = ["version": "v1", "hooks": hooks]
        let data = (try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// ~/.agents/plugins/pip/hooks/hooks.json for Goose.
    static func goose(bridgePath: String) -> String {
        var hooks: [String: Any] = [:]
        for event in ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"] {
            hooks[event] = [["hooks": [["type": "command", "command": HookConfig.command(bridgePath: bridgePath, agent: .goose), "timeout": 5]]]]
        }
        let data = (try? JSONSerialization.data(withJSONObject: ["hooks": hooks], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// ~/.agents/plugins/pip/plugin.json for Goose.
    static func gooseManifest(bridgePath: String) -> String {
        """
        {
          "name": "pip",
          "version": "1.0.0",
          "description": "\(header("Goose"))"
        }

        """
    }

    /// ~/.grok/hooks/pip.json for Grok Build.
    static func grok(bridgePath: String) -> String {
        var hooks: [String: Any] = [:]
        for event in ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "StopFailure", "Notification"] {
            hooks[event] = [["hooks": [["type": "command", "command": HookConfig.command(bridgePath: bridgePath, agent: .grok), "timeout": 5]]]]
        }
        let data = (try? JSONSerialization.data(withJSONObject: ["hooks": hooks], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// A TOML literal string: single quotes, so the double quotes around the bridge path survive as-is.
    static func tomlLiteral(_ text: String) -> String { "'\(text.replacingOccurrences(of: "'", with: ""))'" }

    /// `[[hooks]]` entries for ~/.kimi-code/config.toml. Kimi accepts only event, matcher, command and timeout.
    static func kimi(bridgePath: String) -> String {
        ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "StopFailure"]
            .map { event in
                """
                [[hooks]]
                event = "\(event)"
                command = \(tomlLiteral(HookConfig.command(bridgePath: bridgePath, agent: .kimi)))
                timeout = 5
                """
            }
            .joined(separator: "\n\n")
    }

    /// Pip's entry for the home patch layer, ~/.dsh/cordis.patch.yml (DeepSeek Harness). dsh runs
    /// Claude-style hooks only through its hooks-claude-code bridge, which reads one config file.
    static func dshPatch(hooksPath: String) -> String {
        """
        - insert:
            - id: pip-notch-hooks
              name: '@deepseek-ai/dsh-hooks-claude-code'
              config:
                configPath: '\(hooksPath.replacingOccurrences(of: "'", with: "''"))'
        """
    }

    /// The hooks file the dsh bridge reads. It ignores `async` and has no PermissionRequest or
    /// SessionEnd, so every hook is a short sync call and sessions end when dsh exits.
    static func dshHooks(bridgePath: String) -> String {
        let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"]
            .map { (event: $0, mode: AgentIntegration.Mode.sync(timeout: 5)) }
        let config = HookConfig.installing(.claudeStyle(events), agent: .dsh, bridgePath: bridgePath, into: [:])
        let data = (try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// `[[hooks]]` entries for ~/.vibe/hooks.toml (Mistral Vibe).
    static func vibe(bridgePath: String) -> String {
        ["pre_tool", "post_tool", "post_agent"]
            .map { type in
                """
                [[hooks]]
                name = "pip-\(type.replacingOccurrences(of: "_", with: "-"))"
                type = "\(type)"
                command = \(tomlLiteral(HookConfig.command(bridgePath: bridgePath, agent: .vibe)))
                timeout = 5.0
                description = "Shows this session in the Pip notch."
                """
            }
            .joined(separator: "\n\n")
    }
}
