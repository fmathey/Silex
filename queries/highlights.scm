(identifier) @variable
(qualified_name) @type
(void_type) @type.builtin
(builtin_type) @type.builtin
(type_identifier) @type
(type_identifier (identifier) @type)

(structure_definition
  name: (identifier) @type.definition)

(enum_definition
  name: (identifier) @type.definition)

(protocol_definition
  name: (identifier) @type.definition)

(extension_definition
  target: (named_type) @type)

(protocol_method_requirement
  name: (identifier) @function.method.definition)

(raw_enum_type) @type.builtin

(enum_variant
  name: (identifier) @constant)

(match_branch
  variant: (identifier) @constant)

(match_binding
  name: (identifier) @variable)

(type_parameter
  name: (identifier) @type)

(generic_type
  name: (type_identifier) @type)

(use_declaration
  type: (_)
  alias: (identifier) @type.definition)

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
(drop_definition "drop" @function.definition)

(super_method_expression
  method: (identifier) @function.method.call)

(lambda_expression "func" @keyword)
(lambda_expression deferred: "deferred" @keyword)
(function_type "func" @type.builtin)
(function_type deferred: "deferred" @keyword)
(function_type_parameter mutable_reference: "&" @type)
(function_type_parameter read_reference: "@" @type)

(native_function_declaration
  name: (identifier) @function.definition)

(native_function_declaration
  native: (identifier) @keyword)

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
(parameter
  read_reference: "@" @type)
(mutable_reference_expression
  operator: "&" @operator)
(read_reference_expression "@" @operator)
(self_expression) @keyword
(comment) @comment

[
  "["
  "]"
] @punctuation.bracket

[
  "use"
  "private"
  "public"
  "protected"
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
  "try"
  "move"
  "deferred"
  "struct"
  "protocol"
  "extend"
  "enum"
  "match"
  "class"
  "init"
  "drop"
  "super"
  "override"
  "static"
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
  "=>"
] @operator
