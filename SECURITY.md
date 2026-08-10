# Security guardrails

- Không bao giờ dùng Supabase project/ref, URL, Auth user, hosting project hoặc khóa của hệ thống nguồn.
- Publishable key có thể ở browser; secret/service key chỉ ở server secret store.
- Không commit .env, dump database, danh sách nhân sự, lương, đơn giá nhạy cảm hoặc file backup.
- RLS phải bật; RPC SECURITY DEFINER phải cố định search_path và tự kiểm tra role.
- Import và archive chạy transaction, idempotent và fail-closed.
- Trước production: quét secret, dependency audit, test RLS và thử phục hồi backup.
