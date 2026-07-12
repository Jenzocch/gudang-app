# Use local time for user-facing dates — `toISOString()` is UTC and shifts the day in Indonesia (UTC+7).

Indonesia is UTC+7, so taking a date via `toISOString()` gives the wrong
day/month before 07:00 local. Any user-facing date boundary (today's date,
"before this date" filters, expiry comparisons) must be computed in local time.

**How:** build dates manually like `today()` does —
`d.getFullYear()+'-'+pad(d.getMonth()+1)+'-'+pad(d.getDate())` — not from the
UTC ISO string.

Evidence: `index.html` `today()` and its comment.
