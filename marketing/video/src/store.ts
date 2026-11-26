export const STORE_SIZE = { width: 1320, height: 2868 };

export const STORE_CAPTURE = { width: 1320, height: 2868 };

export const TELEGRAM_FRAME = 540;

export type StoreScreen =
  | "telegram"
  | "store-webhook"
  | "store-history"
  | "store-home"
  | "store-destinations"
  | "store-automate";

export type StoreShot = { slug: string; screen: StoreScreen; kicker: string; title: string };

export const STORE_SHOTS: StoreShot[] = [
  { slug: "telegram", screen: "telegram", kicker: "> telegram", title: "Apple Health, every evening, to your AI agent" },
  { slug: "webhook", screen: "store-webhook", kicker: "$ pulse remote add webhook", title: "POST to any endpoint you own" },
  { slug: "history", screen: "store-history", kicker: "$ git log --oneline", title: "One commit per day, in your own repo" },
  { slug: "home", screen: "store-home", kicker: "$ pulse commit --since=today", title: "Export now, or let Shortcuts run it" },
  { slug: "destinations", screen: "store-destinations", kicker: "$ pulse remote -v", title: "Telegram, GitHub and your webhook" },
  { slug: "automate", screen: "store-automate", kicker: "$ shortcuts run \"Export Today\"", title: "Today at 21:00 or yesterday at 08:30" },
];

export const CAPTURED_SCREENS = STORE_SHOTS.map((s) => s.screen).filter((s) => s !== "telegram");

export function storeFileName(index: number): string {
  return `${String(index + 1).padStart(2, "0")}-${STORE_SHOTS[index].slug}.png`;
}
