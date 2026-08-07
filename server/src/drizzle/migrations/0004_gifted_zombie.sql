ALTER TABLE "attachments" DROP CONSTRAINT "attachments_user_id_transaction_id_transactions_user_id_id_fk";
--> statement-breakpoint
ALTER TABLE "attachments" ADD CONSTRAINT "attachments_user_id_transaction_id_transactions_user_id_id_fk" FOREIGN KEY ("user_id","transaction_id") REFERENCES "public"."transactions"("user_id","id") ON DELETE cascade ON UPDATE no action;