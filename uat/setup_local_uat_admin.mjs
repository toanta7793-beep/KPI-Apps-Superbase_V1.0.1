// Tạo tài khoản ADMIN dùng một lần cho UAT trên stack Postgres CỤC BỘ.
// KHÔNG dùng cho staging/production — ở đó Admin đầu tiên phải tạo bằng luồng
// Invite của Supabase Dashboard, không đặt mật khẩu qua script.
//
//   node uat/setup_local_uat_admin.mjs
//
// In ra mật khẩu dùng một lần; không ghi mật khẩu vào Git.

import { readFileSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { execFileSync } from "node:child_process";

const env = Object.fromEntries(
  readFileSync(new URL("../web/.env.development.local", import.meta.url), "utf8")
    .split(/\r?\n/)
    .filter(l => l && !l.startsWith("#") && l.includes("="))
    .map(l => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]),
);

const url = env.NEXT_PUBLIC_SUPABASE_URL;
const secret = env.SUPABASE_SECRET_KEY;
if (!/^http:\/\/(127\.0\.0\.1|localhost):/.test(url ?? "")) {
  console.error(`Từ chối: script này chỉ chạy với Supabase cục bộ, đang thấy ${url}`);
  process.exit(1);
}

const email = "uat.admin@local.test";
const password = "Uat-" + randomBytes(9).toString("base64url");

const res = await fetch(`${url}/auth/v1/admin/users`, {
  method: "POST",
  headers: { apikey: secret, Authorization: `Bearer ${secret}`, "Content-Type": "application/json" },
  body: JSON.stringify({ email, password, email_confirm: true }),
});
const body = await res.json();
if (!res.ok) { console.error("Tạo user thất bại:", body); process.exit(1); }

execFileSync("docker", [
  "exec", "supabase_db_kpi-enterprise-platform",
  "psql", "-U", "postgres", "-d", "postgres", "-c",
  `insert into public.profiles(auth_user_id, role_code, is_active, display_name)
   values ('${body.id}','ADMIN',true,'UAT Admin')
   on conflict do nothing;`,
], { stdio: "inherit" });

console.log(`\nTài khoản UAT cục bộ:\n  email:    ${email}\n  password: ${password}\n`);
