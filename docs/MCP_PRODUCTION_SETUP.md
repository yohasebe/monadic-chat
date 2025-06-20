# MCP Production Setup Guide

!> **Warning**: MCP server functionality is experimental. This guide provides best practices for production deployment, but the feature itself may change significantly in future releases.

## Electron App Configuration

### macOS Setup
```json
{
  "mcpServers": {
    "monadic-chat-help": {
      "command": "/Applications/Monadic Chat.app/Contents/Resources/app/docker/services/ruby/bin/mcp_proxy.rb",
      "env": {
        "MCP_SERVER_URL": "http://localhost:3100/mcp",
        "MCP_DEBUG": "false"
      }
    }
  }
}
```

### Windows Setup
```json
{
  "mcpServers": {
    "monadic-chat-help": {
      "command": "C:\\Program Files\\Monadic Chat\\resources\\app\\docker\\services\\ruby\\bin\\mcp_proxy.rb",
      "env": {
        "MCP_SERVER_URL": "http://localhost:3100/mcp",
        "MCP_DEBUG": "false"
      }
    }
  }
}
```

## Remote Server Configuration

MCPプロトコルは現在、セキュリティ上の理由からローカルホスト接続のみをサポートしています。リモートサーバーへの接続が必要な場合は、以下のオプションがあります：

### Option 1: SSH Port Forwarding
```bash
# リモートサーバーのMCPポートをローカルにフォワード
ssh -L 3100:localhost:3100 user@remote-server

# Claude Desktop設定はlocalhostのまま使用
```

### Option 2: VPN Connection
VPN経由でリモートサーバーに接続し、プライベートIPアドレスを使用

### Option 3: Reverse Proxy with Authentication
リモートサーバーにNginxなどのリバースプロキシを設定し、認証を追加：

```nginx
server {
    listen 443 ssl;
    server_name mcp.example.com;
    
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location /mcp {
        auth_basic "MCP Access";
        auth_basic_user_file /etc/nginx/.htpasswd;
        
        proxy_pass http://localhost:3100;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

## Security Considerations

1. **Authentication**: MCPサーバーは現在認証機能を持たないため、ローカルホスト限定で動作
2. **Network Isolation**: 本番環境ではファイアウォールで3100ポートを外部からアクセス不可に設定
3. **SSL/TLS**: リモートアクセスが必要な場合は、必ずHTTPS経由で暗号化

## Electron App Distribution

Electronアプリをパッケージ化する際、以下のファイルが含まれることを確認：

1. MCPプロキシスクリプト: `docker/services/ruby/bin/mcp_proxy.rb`
2. MCPサーバーモジュール: `docker/services/ruby/lib/monadic/mcp/`
3. 設定ファイルテンプレート: `docs/claude_desktop_config_template.json`

## Troubleshooting

### プロキシスクリプトが見つからない場合
1. Electronアプリの実際のインストールパスを確認
2. `ls -la "/Applications/Monadic Chat.app/Contents/Resources/app/"` でファイル構造を確認
3. 必要に応じてプロキシスクリプトを別の場所にコピー

### ポート競合
デフォルトポート3100が使用中の場合：
1. `~/monadic/config/env`で`MCP_SERVER_PORT=3101`などに変更
2. Claude Desktop設定のURLも同じポートに変更

### 接続タイムアウト
1. Monadic Chatが起動していることを確認
2. MCPサーバーが有効になっていることを確認（Web UIの設定パネル）
3. ファイアウォールがローカル接続をブロックしていないか確認