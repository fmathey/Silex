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

(assignment_statement
  left: (identifier) @variable)

(string_literal) @string
(escape_sequence) @string.escape
(integer_literal) @number
(float_literal) @number
(boolean_literal) @boolean
(self_expression) @variable.builtin
(comment) @comment

[
  "import"
  "use"
  "pub"
  "as"
  "let"
  "var"
  "if"
  "else"
  "while"
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
] @operator
