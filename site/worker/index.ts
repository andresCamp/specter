import Stripe from "stripe";

// Stateless crypto provider for webhook signature verification (Workers have no Node crypto).
const webCrypto = Stripe.createSubtleCryptoProvider();

const MAX_ACTIVATIONS = 10;

// Unambiguous alphabet — no 0/O/1/I/L.
const KEY_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

interface LicenseRecord {
  key: string;
  email: string | null;
  sessionId: string;
  createdAt: string;
  activations: number;
}

function getStripe(env: Env): Stripe {
  return new Stripe(env.STRIPE_SECRET_KEY, {
    httpClient: Stripe.createFetchHttpClient(),
  });
}

function generateLicenseKey(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  const chars = Array.from(bytes, (b) => KEY_ALPHABET[b % KEY_ALPHABET.length]);
  const groups = [];
  for (let i = 0; i < 16; i += 4) groups.push(chars.slice(i, i + 4).join(""));
  return `SPECTR-${groups.join("-")}`;
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Idempotent: one license per checkout session, keyed both ways in KV.
async function issueLicense(
  env: Env,
  session: Stripe.Checkout.Session
): Promise<string> {
  const existing = await env.LICENSES.get(`session:${session.id}`);
  if (existing) return existing;

  const key = generateLicenseKey();
  const record: LicenseRecord = {
    key,
    email: session.customer_details?.email ?? null,
    sessionId: session.id,
    createdAt: new Date().toISOString(),
    activations: 0,
  };
  await env.LICENSES.put(`license:${key}`, JSON.stringify(record));
  await env.LICENSES.put(`session:${session.id}`, key);
  return key;
}

async function handleCheckout(request: Request, env: Env): Promise<Response> {
  const origin = new URL(request.url).origin;
  const session = await getStripe(env).checkout.sessions.create({
    mode: "payment",
    line_items: [{ price: env.STRIPE_PRICE_ID, quantity: 1 }],
    success_url: `${origin}/thanks?session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${origin}/#pricing`,
    allow_promotion_codes: true,
  });
  if (!session.url) return json({ error: "checkout_unavailable" }, 502);
  return Response.redirect(session.url, 303);
}

async function handleWebhook(request: Request, env: Env): Promise<Response> {
  const signature = request.headers.get("Stripe-Signature");
  if (!signature) return json({ error: "missing_signature" }, 400);

  const body = await request.text();
  let event: Stripe.Event;
  try {
    event = await getStripe(env).webhooks.constructEventAsync(
      body,
      signature,
      env.STRIPE_WEBHOOK_SECRET,
      undefined,
      webCrypto
    );
  } catch (err) {
    console.log(JSON.stringify({ event: "webhook_bad_signature", error: String(err) }));
    return json({ error: "bad_signature" }, 400);
  }

  if (event.type === "checkout.session.completed") {
    const session = event.data.object;
    if (session.payment_status === "paid") {
      await issueLicense(env, session);
    }
  }
  return json({ received: true });
}

// Success page exchanges its session_id for the license key.
// Falls back to issuing directly if the webhook hasn't landed yet.
async function handleLicense(request: Request, env: Env): Promise<Response> {
  const sessionId = new URL(request.url).searchParams.get("session_id");
  if (!sessionId || !sessionId.startsWith("cs_")) {
    return json({ error: "invalid_session" }, 400);
  }

  const existing = await env.LICENSES.get(`session:${sessionId}`);
  if (existing) return json({ key: existing });

  const session = await getStripe(env).checkout.sessions.retrieve(sessionId);
  if (session.payment_status !== "paid") {
    return json({ error: "not_paid" }, 402);
  }
  return json({ key: await issueLicense(env, session) });
}

// The Mac app posts { key } to activate.
async function handleActivate(request: Request, env: Env): Promise<Response> {
  let key: string;
  try {
    const payload = (await request.json()) as { key?: string };
    key = (payload.key ?? "").trim().toUpperCase();
  } catch {
    return json({ valid: false, error: "bad_request" }, 400);
  }
  if (!key.startsWith("SPECTR-")) return json({ valid: false }, 404);

  const raw = await env.LICENSES.get(`license:${key}`);
  if (!raw) return json({ valid: false }, 404);

  const record = JSON.parse(raw) as LicenseRecord;
  if (record.activations >= MAX_ACTIVATIONS) {
    return json({ valid: false, error: "activation_limit" }, 403);
  }
  record.activations += 1;
  await env.LICENSES.put(`license:${key}`, JSON.stringify(record));
  return json({ valid: true });
}

export default {
  async fetch(request, env): Promise<Response> {
    const { pathname } = new URL(request.url);
    try {
      if (pathname === "/api/checkout" && request.method === "GET") {
        return await handleCheckout(request, env);
      }
      if (pathname === "/api/webhook" && request.method === "POST") {
        return await handleWebhook(request, env);
      }
      if (pathname === "/api/license" && request.method === "GET") {
        return await handleLicense(request, env);
      }
      if (pathname === "/api/activate" && request.method === "POST") {
        return await handleActivate(request, env);
      }
    } catch (err) {
      console.log(JSON.stringify({ event: "api_error", pathname, error: String(err) }));
      return json({ error: "internal" }, 500);
    }
    // Everything else falls through to the static site.
    return env.ASSETS.fetch(request);
  },
} satisfies ExportedHandler<Env>;
