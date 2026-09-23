# Notes

Personal reference and writing backlog. Distinct from `lessons/`:

| | Holds | Written for | Answers |
|---|---|---|---|
| `lessons/` | what happened in *this repo* and why | an interviewer | "why did you build it that way?" |
| `notes/` | the transferable concept, plainly | future you | "wait, how does that work again?" |

Lesson 010 is *"we lost every index and here's the story."*
`concepts.md` is *"how Postgres indexes actually work."* Same evening, different
artifacts — and you need both, because the story is unusable on another project
and the concept is unusable in an interview about this one.

## Files

- **[concepts.md](concepts.md)** — reference. One entry per concept, appended as
  we hit them. Look things up here.
- **[blog-backlog.md](blog-backlog.md)** — post seeds. Each has a hook, the
  evidence already in hand, and where the material lives. Pick one, write it.

## How to use these

**Read `concepts.md` for reference. Do not paste it into the blog.**

That's the whole discipline. These explanations are mine; a post assembled from
them is not your voice, reads like it, and teaches you nothing. The test that
you've actually got a concept: close the file and explain it to someone who
doesn't have it open. What survives is yours to write.

The `lessons/` entries already carry a **"saying it out loud"** section — a
~60-second first-person version. Those are closer to blog drafts than anything
in here, because they were written as speech.

**Append as you go.** A concept you had to look up twice belongs here after the
second time. A finding with a number attached belongs in the backlog the day you
find it, while you still remember why it surprised you.

## On publishing

This directory is committed, so it's public with the rest of the repo. Reference
notes and a visible writing backlog read fine — arguably well — in a portfolio.
If you'd rather they weren't, `notes/` in `.gitignore` reverses it, though
you'll lose version history for them.
