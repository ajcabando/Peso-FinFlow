ALTER TABLE "attachments" DROP CONSTRAINT "attachments_transaction_id_transactions_id_fk";
--> statement-breakpoint
ALTER TABLE "bills" DROP CONSTRAINT "bills_account_id_accounts_id_fk";
--> statement-breakpoint
ALTER TABLE "budgets" DROP CONSTRAINT "budgets_category_id_accounts_id_fk";
--> statement-breakpoint
ALTER TABLE "ledger_entries" DROP CONSTRAINT "ledger_entries_transaction_id_transactions_id_fk";
--> statement-breakpoint
ALTER TABLE "ledger_entries" DROP CONSTRAINT "ledger_entries_account_id_accounts_id_fk";
--> statement-breakpoint
ALTER TABLE "transaction_tags" DROP CONSTRAINT "transaction_tags_transaction_id_transactions_id_fk";
--> statement-breakpoint
ALTER TABLE "transaction_tags" DROP CONSTRAINT "transaction_tags_tag_id_tags_id_fk";
--> statement-breakpoint
-- Composite (user_id, id) primary keys. Drizzle-kit cannot auto-name the
-- existing PKs, so the drops below are filled in manually (Postgres defaults
-- to "<table>_pkey"). transaction_tags had NO primary key before — nothing
-- to drop there.
ALTER TABLE "accounts" DROP CONSTRAINT "accounts_pkey";--> statement-breakpoint
ALTER TABLE "bills" DROP CONSTRAINT "bills_pkey";--> statement-breakpoint
ALTER TABLE "budgets" DROP CONSTRAINT "budgets_pkey";--> statement-breakpoint
ALTER TABLE "ledger_entries" DROP CONSTRAINT "ledger_entries_pkey";--> statement-breakpoint
ALTER TABLE "tags" DROP CONSTRAINT "tags_pkey";--> statement-breakpoint
ALTER TABLE "transactions" DROP CONSTRAINT "transactions_pkey";--> statement-breakpoint
ALTER TABLE "accounts" ADD CONSTRAINT "accounts_user_id_id_pk" PRIMARY KEY("user_id","id");--> statement-breakpoint
ALTER TABLE "bills" ADD CONSTRAINT "bills_user_id_id_pk" PRIMARY KEY("user_id","id");--> statement-breakpoint
ALTER TABLE "budgets" ADD CONSTRAINT "budgets_user_id_id_pk" PRIMARY KEY("user_id","id");--> statement-breakpoint
ALTER TABLE "ledger_entries" ADD CONSTRAINT "ledger_entries_user_id_id_pk" PRIMARY KEY("user_id","id");--> statement-breakpoint
ALTER TABLE "tags" ADD CONSTRAINT "tags_user_id_id_pk" PRIMARY KEY("user_id","id");--> statement-breakpoint
ALTER TABLE "transaction_tags" ADD CONSTRAINT "transaction_tags_user_id_transaction_id_tag_id_pk" PRIMARY KEY("user_id","transaction_id","tag_id");--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_user_id_id_pk" PRIMARY KEY("user_id","id");--> statement-breakpoint
ALTER TABLE "attachments" ADD CONSTRAINT "attachments_user_id_transaction_id_transactions_user_id_id_fk" FOREIGN KEY ("user_id","transaction_id") REFERENCES "public"."transactions"("user_id","id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bills" ADD CONSTRAINT "bills_user_id_account_id_accounts_user_id_id_fk" FOREIGN KEY ("user_id","account_id") REFERENCES "public"."accounts"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "budgets" ADD CONSTRAINT "budgets_user_id_category_id_accounts_user_id_id_fk" FOREIGN KEY ("user_id","category_id") REFERENCES "public"."accounts"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ledger_entries" ADD CONSTRAINT "ledger_entries_user_id_transaction_id_transactions_user_id_id_fk" FOREIGN KEY ("user_id","transaction_id") REFERENCES "public"."transactions"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ledger_entries" ADD CONSTRAINT "ledger_entries_user_id_account_id_accounts_user_id_id_fk" FOREIGN KEY ("user_id","account_id") REFERENCES "public"."accounts"("user_id","id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transaction_tags" ADD CONSTRAINT "transaction_tags_user_id_transaction_id_transactions_user_id_id_fk" FOREIGN KEY ("user_id","transaction_id") REFERENCES "public"."transactions"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transaction_tags" ADD CONSTRAINT "transaction_tags_user_id_tag_id_tags_user_id_id_fk" FOREIGN KEY ("user_id","tag_id") REFERENCES "public"."tags"("user_id","id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
