# Style

The code should be boring to read and hard to misuse.

## Files

Each source file should have one clear responsibility. A reader should be able
to infer the module's purpose from the file name and the first comment block.

Large files are acceptable only when the domain is genuinely large and the
file has clear sections. As a rule of thumb, prefer files below 1,200 lines.

## Names

- Public constructors and accessors keep descriptive names.
- Internal helpers should use a narrow module prefix or a leading `%`.
- Predicates end in `-p`.
- Functions that mutate state should make that visible with verbs such as
  `put`, `set`, `remove`, `commit`, `restore`, or `apply`.

## Comments

Write comments for:

- module responsibility;
- protocol invariants;
- non-obvious compatibility behavior;
- failure contracts at external boundaries.

Do not write comments that merely repeat the function name or translate a
single expression.

## Validation

External input should be decoded and validated once at the boundary. Internal
code should receive typed domain values where practical.

Error messages should name the bad field and the expected shape.

## Tests

Tests should be organized by domain, not by historical implementation file.
Large regression suites should expose small helper builders so individual
failure cases stay readable.
