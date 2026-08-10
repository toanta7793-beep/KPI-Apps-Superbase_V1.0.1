# Kiến trúc bản sao độc lập

```text
Người dùng -> Frontend Web App -> Supabase Auth -> RPC/Data API -> PostgreSQL
                                      |
                                      +-> Storage (backup tuần)
```

## Biên hệ thống

- Browser chỉ nhận Supabase URL và publishable key.
- Secret/server key chỉ tồn tại ở biến môi trường phía server cho API quản trị người dùng và archive.
- RLS và RPC là lớp kiểm soát quyền chính; UI không phải ranh giới bảo mật.
- Mỗi môi trường có Supabase project, URL, Auth users, Storage, migration history và backup riêng.
- Không dùng Google Sheet hay Apps Script làm runtime của clone này. Chỉ nhập dữ liệu qua file/luồng được kiểm tra.

## Nhóm dữ liệu

- Cấu hình: systems, salary_grades, salary_standards, work_categories, price_items.
- Tổ chức: teams, workers, profiles, profile_teams, roles.
- Vận hành: jobs, assignments, work_weeks, shared_work_weeks.
- Kiểm soát: job_history, pgv_print_log, pgv_save_operations, week_archive_operations, worker_roster_import_backups.
- ETL/đối soát: staging.*, mapping.*, reconciliation.*.

## Tối ưu đồng thời

- Idempotency bằng request_key cho thao tác có thể bấm lặp.
- Transaction trong RPC cho nhập danh sách, gộp việc, lưu PGV và archive.
- Constraint/index/RLS ở database; không phụ thuộc validation phía trình duyệt.
- Archive tuần là quy trình hai pha: prepare snapshot -> ghi backup -> finalize.
