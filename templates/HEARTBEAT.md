# Heartbeat checklist

<!--
  This file is read by the heartbeat loop every 30 minutes.
  Keep it short. Add specific checks below.
  Each entry should be self-contained (the heartbeat agent has no prior context)
  and specific about what counts as an alert vs. nothing-to-report.
  If nothing needs attention after running checks, reply HEARTBEAT_OK.

  Alert routing: when the agent's reply is anything other than HEARTBEAT_OK,
  the main session forwards it to Telegram via the official channel plugin
  (using the chat_id cached at ~/.claude/channels/telegram/last_chat.txt).
  HEARTBEAT_OK replies are silent — no Telegram, no alert.
-->
