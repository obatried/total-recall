# Memory index

This file is loaded into context every session. It is an INDEX, not a store — one line
per memory or domain, never the content itself. Domain indexes (topics/, projects/) load
on demand when a session touches them. Leaf notes load only when an index points to them.

Replace these examples with your own as you go. New notes auto-add themselves here (or to
their topic/project index) via the autoindex hook.

## Core rules (always loaded)
- [example-feedback-rule](feedback_example.md) — name notes by the words you'd search for.
- [example-user-fact](user_example.md) — a durable fact about the user.

## Topics (load on mention)
- [Example topic](topics/example-topic.md) — what this domain covers.

## Projects (load on mention)
- [Example project](projects/example-project.md) — current state of an ongoing project.
