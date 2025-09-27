# Alex0001 WeChat ↔ ChatGPT Bridge

该项目提供一个轻量级的 Flask 网站，用于接收来自微信公众号服务器的消息，将文本内容转发给 OpenAI ChatGPT，并把生成的回复再发送回微信对话。

## 功能概述
- 验证来自微信服务器的请求签名，确保消息来源可靠。
- 解析微信推送的 XML 消息，支持文本消息类型。
- 调用 OpenAI Chat Completions 接口，让 ChatGPT 生成回复。
- 以符合微信要求的 XML 格式返回回复消息。

## 快速开始
1. **安装依赖**
   ```bash
   pip install -r requirements.txt
   ```

2. **配置环境变量**
   - `WECHAT_TOKEN`：在微信公众平台配置的令牌，需要与平台保持一致。
   - `OPENAI_API_KEY`：OpenAI 的 API Key。
   - （可选）`OPENAI_MODEL`：指定使用的模型，默认 `gpt-3.5-turbo`。

   在本地开发时可以通过导出环境变量或使用 `.env` 文件（需自行创建并确保不提交到版本库）。

3. **启动服务**
   ```bash
   python app.py
   ```
   服务会在 `0.0.0.0:8000` 监听，便于微信服务器访问。

4. **在微信公众平台配置服务器**
   - URL：指向部署后的 `/wechat` 路径，例如 `https://example.com/wechat`。
   - Token：与 `WECHAT_TOKEN` 环境变量保持一致。
   - 消息加解密方式：当前示例仅支持明文模式。

## 扩展建议
- 若需支持图文、语音等更多消息类型，可在 `app.py` 中扩展 `WeChatMessage` 处理逻辑。
- 可在调用 ChatGPT 时加入对话上下文缓存或数据库，用于构建多轮对话。
- 若要支持微信安全模式，请集成消息体的 AES 解密/加密流程。

## 免责声明
该项目仅提供示例代码，实际生产环境部署需确保安全性、错误处理和日志记录等方面符合要求。
