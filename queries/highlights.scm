(identifier) @variable
(void_type) @type.builtin
(builtin_type) @type.builtin

(function_definition
  name: (identifier) @function.definition)

(print_statement
  function: (identifier) @function.call)

(variable_declaration
  name: (identifier) @variable)

(assignment_statement
  left: (identifier) @variable)

(string_literal) @string
(escape_sequence) @string.escape
(integer_literal) @number
(boolean_literal) @boolean
(comment) @comment

[
  "let"
  "var"
  "if"
  "else"
  "while"
] @keyword

[
  "+"
  "-"
  "*"
  "/"
  "="
  "=="
  "!="
  "<"
  "<="
  ">"
  ">="
  "!"
  "&&"
  "||"
] @operator
