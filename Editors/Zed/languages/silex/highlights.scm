(identifier) @variable
(module_path) @namespace
(qualified_name) @type
(void_type) @type.builtin
(builtin_type) @type.builtin
(type_identifier) @type
(type_identifier (identifier) @type)

(structure_definition
  name: (identifier) @type.definition)

(structure_field
  name: (identifier) @property)

(structure_initializer
  type: [(identifier) (qualified_name)] @type)

(field_initializer
  name: (identifier) @property)

(member_expression
  field: (identifier) @property)

(function_definition
  name: (identifier) @function.definition)

(print_statement
  function: (identifier) @function.call)

(call_expression
  function: (identifier) @function.call)

(method_call_expression
  method: (identifier) @function.method.call)

(parameter
  name: (identifier) @variable.parameter)

(variable_declaration
  name: (identifier) @variable)

(for_statement
  name: (identifier) @variable)

[(break_statement) (continue_statement)] @keyword

(assignment_statement
  left: (identifier) @variable)

(string_literal) @string
(escape_sequence) @string.escape
(integer_literal) @number
(float_literal) @number
(boolean_literal) @boolean
(conversion_expression
  "as" @keyword
  type: (type) @type)
(reference_type
  kind: ["&" "@"] @type)
(borrow_expression
  operator: "&" @operator)
(move_expression
  "move" @keyword)
(self_expression) @variable.builtin
(comment) @comment

[
  "import"
  "use"
  "pub"
  "as"
  "move"
  "let"
  "var"
  "if"
  "else"
  "while"
  "for"
  "in"
  "return"
  "struct"
  "func"
] @keyword

[
  "+"
  "-"
  "*"
  "/"
  "="
  "+="
  "-="
  "*="
  "/="
  "++"
  "--"
  "=="
  "!="
  "<"
  "<="
  ">"
  ">="
  "!"
  "&&"
  "||"
  "^"
] @operator

[
  "("
  ")"
  "{"
  "}"
  "["
  "]"
] @punctuation.bracket

[
  ":"
  ","
  ";"
] @punctuation.delimiter
