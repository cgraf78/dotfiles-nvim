# Extracted core test helpers

The files in this directory are the editor-only portions of the former
top-level dotfiles test helpers. They deliberately use the synthetic capability
HOME supplied by `test/run` and never inspect the live user environment.
