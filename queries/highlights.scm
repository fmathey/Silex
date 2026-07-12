(identifier) @variable
(builtin_type) @type.builtin

(function_definition
  name: (identifier) @function.definition)

(call_expression
  function: (identifier) @function.call)

(parameter
  name: (identifier) @variable.parameter)

(string_literal) @string
(escape_sequence) @string.escape
(boolean_literal) @boolean
(number_literal) @number
(comment) @comment
"return" @keyword.return
