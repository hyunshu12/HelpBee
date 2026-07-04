CREATE TABLE IF NOT EXISTS "inquiries" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"email" text NOT NULL,
	"message" text NOT NULL,
	"locale" text,
	"status" text DEFAULT 'new' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "inquiries_status_idx" ON "inquiries" ("status");--> statement-breakpoint
CREATE INDEX IF NOT EXISTS "inquiries_created_at_idx" ON "inquiries" ("created_at");--> statement-breakpoint
-- ─────────────────── CHECK constraints ───────────────────
-- drizzle-kit@0.20.x는 check() 호출을 SQL로 emit하지 않으므로 수동 보강 (0000 migration과 동일 컨벤션).
ALTER TABLE "inquiries" ADD CONSTRAINT "inquiries_status_check" CHECK ("status" IN ('new', 'answered', 'closed'));