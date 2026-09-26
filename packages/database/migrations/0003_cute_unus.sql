ALTER TABLE "analyses" ADD COLUMN "vdi" numeric(6, 3);--> statement-breakpoint
ALTER TABLE "analyses" ADD COLUMN "vdi_ci_low" numeric(6, 3);--> statement-breakpoint
ALTER TABLE "analyses" ADD COLUMN "vdi_ci_high" numeric(6, 3);--> statement-breakpoint
ALTER TABLE "analyses" ADD COLUMN "bee_total" integer;--> statement-breakpoint
ALTER TABLE "analyses" ADD COLUMN "bee_infested" integer;