# Anytype + Claude MCP Setup (Self-Hosted)

This guide covers integrating a self-hosted Anytype instance (running on a VPS) with Claude Desktop via the Model Context Protocol (MCP).

## Prerequisites

- **Anytype Desktop** (v0.46.0 or later) installed locally.
- **Node.js** installed locally (to run `npx`).
- **Claude Desktop** app installed.
- Access to your VPS `client-config.yml`.

---

## Step 1: Connect Local Anytype to VPS

Anytype's API currently runs through the desktop client. You must point your local app to your self-hosted node.

1. **Log Out** of Anytype on your computer.
2. On the onboarding screen, click the **Gear Icon** (top right).
3. Set the **Network** field to **Self-hosted**.
4. Upload your VPS `client-config.yml` file and click **Save**.
5. Log back into your identity.

## Step 2: Generate API Key

1. In Anytype, go to **App Settings > API Keys**.
2. Click **Create new**.
3. **Copy the Bearer Token** immediately; it will not be shown again.

## Step 3: Configure Claude Desktop

1. Open Claude Desktop.
2. Go to **Settings > Developer > Edit Config**. This opens `claude_desktop_config.json`.
3. Add the following configuration (replace `<YOUR_API_KEY>` with your token):

```json
{
  "mcpServers": {
    "anytype": {
      "command": "npx",
      "args": ["-y", "@anyproto/anytype-mcp"],
      "env": {
        "OPENAPI_MCP_HEADERS": "{\"Authorization\":\"Bearer <YOUR_API_KEY>\"}"
      }
    }
  }
}
```

## Step 4: Verify Connection

1. **Restart Claude Desktop** completely (Quit and Re-open).
2. Look for the **Plug Icon** in the bottom right of the chat bar to confirm the server is active.
3. **Test a command**: Ask Claude, _"What are the names of my Anytype spaces?"_ or _"Create a new note in Anytype called 'Claude Test'."_
