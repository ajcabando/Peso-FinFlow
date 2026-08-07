DROP INDEX "sync_ops_entity_version_unique";--> statement-breakpoint
CREATE INDEX "sync_ops_user_entity_seq_idx" ON "sync_ops" USING btree ("user_id","entity","entity_id","seq");