extends RefCounted
## Rolls routine news (births, coming of age) into one line every EVERY seconds,
## so a village of 100 doesn't bury the alarms.

const EVERY := 30.0
const ROLLED := {
	"birth": ["%d child was born.", "%d children were born."],
	"grown": ["%d child has grown up and can work.", "%d children have grown up and can work."],
}

var waiting := {}       # kind -> how many
var last_shown := {}    # kind -> match time


## The line to show now, or "" when the message joins the next summary.
func take(msg: Dictionary, now: float) -> String:
	var kind: String = msg["kind"]
	if not ROLLED.has(kind):
		return msg["text"]
	if not waiting.has(kind) and now - float(last_shown.get(kind, -EVERY)) >= EVERY:
		last_shown[kind] = now
		return msg["text"]
	waiting[kind] = int(waiting.get(kind, 0)) + 1
	return ""


## Summaries that are due, as [text, kind] pairs.
func due(now: float) -> Array:
	var out := []
	for kind in waiting.keys():
		if now - float(last_shown.get(kind, -EVERY)) < EVERY:
			continue
		var n: int = waiting[kind]
		out.append([ROLLED[kind][0 if n == 1 else 1] % n, kind])
		last_shown[kind] = now
		waiting.erase(kind)
	return out
