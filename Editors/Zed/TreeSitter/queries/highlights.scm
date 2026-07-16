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

(field_initializer
  name: (identifier) @property)

(member_expression
  field: (identifier) @property)
(safe_member_expression
  field: (identifier) @property)

(function_definition
  name: (identifier) @function.definition)

(constructor_definition "init" @function.definition)

(super_method_expression
  method: (identifier) @function.method.call)

(lambda_expression "func" @keyword)
(function_type "func" @type.builtin)
(function_type_parameter mutable_reference: "&" @type)

(print_statement
  function: (identifier) @function.call)

(assert_statement
  function: (identifier) @keyword)

(panic_statement
  function: (identifier) @keyword)

(cascade_operation
  operator: ".." @operator)

(integer_range
  operator: "..." @operator)

(cascade_method_call
  method: (identifier) @function.method.call)

(cascade_field_assignment
  field: (identifier) @property)

(cascade_terminal_operation
  method: (identifier) @function.method.call)

(cascade_terminal_operation
  field: (identifier) @property)

(parameter
  name: (identifier) @variable.parameter)

(variable_declaration
  name: (identifier) @variable)

(for_statement
  name: (identifier) @variable)
(conditional_binding
  name: (identifier) @variable)

[(break_statement) (continue_statement)] @keyword

(assignment_statement
  left: (identifier) @variable)

(string_literal) @string
(escape_sequence) @string.escape
(integer_literal) @number
(float_literal) @number
(boolean_literal) @boolean
(null_literal) @constant.builtin
(parameter
  mutable_reference: "&" @type)
(borrow_expression
  operator: "&" @operator)
(self_expression) @keyword
(comment) @comment

[
  "["
  "]"
] @punctuation.bracket

[
  "import"
  "use"
  "pub"
  "sub"
  "as"
  "let"
  "var"
  "if"
  "elif"
  "else"
  "while"
  "for"
  "range"
  "in"
  "return"
  "struct"
  "class"
  "init"
  "super"
  "override"
  "func"
] @keyword

[
  "+"
  "-"
  "*"
  "/"
  "%"
  "&"
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
  "?"
  "?."
] @operator
