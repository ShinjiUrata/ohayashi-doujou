import { serve } from "@hono/node-server";
import { Hono } from "hono";
import { config } from "./config.js";
import { checkIdRoute } from "./routes/check-id.js";
import { publishRoute } from "./routes/publish.js";

/**
 * お囃子道場 API のエントリポイント。
 * Cloud Run 上で動作、iOS アプリから匿名 POST を受け付ける。
 */

const app = new Hono();

// ヘルスチェック (Cloud Run の readiness 用)
app.get("/", (c) =>
  c.json({
    service: "ohayashi-doujou-api",
    environment: config.environment,
    ok: true,
  }),
);

app.route("/", checkIdRoute);
app.route("/", publishRoute);

serve(
  {
    fetch: app.fetch,
    port: config.port,
  },
  (info) => {
    console.log(
      JSON.stringify({
        severity: "INFO",
        message: "server listening",
        port: info.port,
        environment: config.environment,
      }),
    );
  },
);
