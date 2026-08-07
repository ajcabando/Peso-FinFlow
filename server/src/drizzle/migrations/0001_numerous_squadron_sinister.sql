ALTER TABLE "devices" ALTER COLUMN "id" DROP DEFAULT;--> statement-breakpoint
CREATE INDEX "refresh_tokens_device_idx" ON "refresh_tokens" USING btree ("device_id");