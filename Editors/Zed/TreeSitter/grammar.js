const PREC = {
  logicalOr: 1,
  logicalAnd: 2,
  equality: 3,
  comparison: 4,
  bitXor: 5,
  bitAnd: 6,
  shift: 7,
  additive: 8,
  multiplicative: 9,
  unary: 10,
  conversion: 11,
  member: 12,
};

module.exports = grammar({
  name: "silex",

  extras: ($) => [/\s/, $.comment],
  word: ($) => $.identifier,
  externals: ($) => [$._automatic_semicolon],
  conflicts: ($) => [[$.array_type, $.type], [$.optional_type, $.type]],

  rules: {
    source_file: ($) =>
      repeat(
        choice(
          $.import_declaration,
          $.use_declaration,
          $.enum_definition,
          $.structure_definition,
          $.function_definition,
          $.native_function_declaration,
          $.public_declaration,
        ),
      ),

    import_declaration: ($) =>
      seq(
        "import",
        field("module", $.module_path),
        optional(seq("as", field("alias", $.identifier))),
        choice(";", $._automatic_semicolon),
      ),

    use_declaration: ($) =>
      seq(
        optional(field("visibility", "pub")),
        "use",
        choice(
          prec(1, seq(
            field("declaration", choice($.qualified_name, $.identifier)),
            optional(seq("as", field("alias", $.identifier))),
          )),
          seq(
            field("type", $.type),
            "as",
            field("alias", $.identifier),
          ),
        ),
        choice(";", $._automatic_semicolon),
      ),

    public_declaration: ($) =>
      seq(field("visibility", "pub"), choice($.enum_definition, $.structure_definition, $.function_definition)),

    enum_definition: ($) =>
      seq(
        "enum",
        field("name", $.identifier),
        optional(field("type_parameters", $.type_parameter_list)),
        optional(seq(":", field("raw_type", $.raw_enum_type))),
        "{",
        repeat1($.enum_variant),
        "}",
      ),

    raw_enum_type: (_) => choice("int", "str"),

    enum_variant: ($) =>
      seq(
        field("name", $.identifier),
        optional(
          field(
            "associated_types",
            seq("(", $.type, repeat(seq(",", $.type)), ")"),
          ),
        ),
        optional(seq("=", field("raw_value", choice($.signed_integer_literal, $.string_literal)))),
        choice(";", $._automatic_semicolon),
      ),

    signed_integer_literal: ($) => seq(optional("-"), $.integer_literal),

    module_path: ($) =>
      seq($.identifier, repeat(seq(".", $.identifier))),

    qualified_name: ($) =>
      seq($.identifier, repeat1(seq(".", $.identifier))),

    structure_definition: ($) =>
      seq(
        choice("struct", "class"),
        field("name", $.identifier),
        optional(field("type_parameters", $.type_parameter_list)),
        optional(seq(":", field("base", $.named_type))),
        "{",
        repeat(
          choice(
            seq(
              optional(field("visibility", choice("pub", "sub"))),
              optional(field("static", "static")),
              $.structure_field,
            ),
            seq(optional(field("visibility", choice("pub", "sub"))), $.constructor_definition),
            $.drop_definition,
            seq(
              optional(field("override", "override")),
              optional(field("visibility", choice("pub", "sub"))),
              optional(field("static", "static")),
              $.function_definition,
            ),
          ),
        ),
        "}",
      ),

    structure_field: ($) =>
      seq(
        field("mutability", choice("let", "var")),
        field("name", $.identifier),
        ":",
        field("type", $.type),
        optional(seq("=", field("default", $.expression))),
        choice(";", $._automatic_semicolon),
      ),

    constructor_definition: ($) =>
      seq(
        "init",
        $.parameter_list,
        optional(seq(":", field("super", "super"), field("arguments", $.argument_list))),
        field("body", $.block),
      ),

    drop_definition: ($) => seq("drop", field("body", $.block)),

    function_definition: ($) =>
      seq(
        "func",
        field("name", $.identifier),
        optional(field("type_parameters", $.type_parameter_list)),
        $.parameter_list,
        optional(field("return_type", choice($.void_type, $.type))),
        field("body", $.block),
      ),

    native_function_declaration: ($) =>
      seq(
        field("native", alias("native", $.identifier)),
        "func",
        field("name", $.identifier),
        $.parameter_list,
        field("return_type", choice($.void_type, $.type)),
        choice(";", $._automatic_semicolon),
      ),

    void_type: (_) => "void",
    builtin_type: (_) =>
      choice(
        "int",
        "int8",
        "int16",
        "int32",
        "int64",
        "uint",
        "uint8",
        "uint16",
        "uint32",
        "uint64",
        "float",
        "float32",
        "float64",
        "bool",
        "str",
      ),
    type_parameter_list: ($) =>
      seq(
        "<",
        $.type_parameter,
        repeat(seq(",", $.type_parameter)),
        ">",
      ),
    type_parameter: ($) => field("name", $.identifier),
    type_argument_list: ($) =>
      seq("<", $.type, repeat(seq(",", $.type)), ">"),
    generic_type: ($) =>
      prec(
        PREC.member,
        seq(
          field("name", alias(choice($.identifier, $.qualified_name), $.type_identifier)),
          field("arguments", $.type_argument_list),
        ),
      ),
    named_type: ($) =>
      choice(alias(choice($.identifier, $.qualified_name), $.type_identifier), $.generic_type),
    function_type: ($) =>
      seq(
        "func",
        "(",
        optional(seq($.function_type_parameter, repeat(seq(",", $.function_type_parameter)))),
        ")",
        optional(choice($.void_type, $.type)),
      ),
    function_type_parameter: ($) =>
      seq(optional(field("mutable_reference", "&")), field("type", $.type)),
    grouped_type: ($) => seq("(", field("type", $.type), ")"),
    optional_type: ($) =>
      prec.left(
        seq(
          field(
            "contained",
            choice($.builtin_type, $.named_type, $.function_type, $.grouped_type, $.array_type),
          ),
          "?",
        ),
      ),
    array_type: ($) =>
      prec.left(
        seq(
          field("element", choice($.builtin_type, $.named_type, $.function_type, $.grouped_type, $.optional_type)),
          repeat1(choice(seq("[", "]"), seq("[", field("length", $.integer_literal), "]"))),
        ),
      ),
    type: ($) => choice($.optional_type, $.array_type, $.grouped_type, $.function_type, $.builtin_type, $.named_type),
    parameter_list: ($) =>
      seq("(", optional(seq($.parameter, repeat(seq(",", $.parameter)))), ")"),

    argument_list: ($) =>
      seq("(", optional(seq($.expression, repeat(seq(",", $.expression)))), ")"),

    parameter: ($) =>
      seq(
        field("name", $.identifier),
        ":",
        optional(field("mutable_reference", "&")),
        field("type", $.type),
      ),

    block: ($) => seq("{", repeat($.statement), "}"),

    statement: ($) =>
      choice(
        seq(
          choice(
            $.variable_declaration,
            $.assignment_statement,
            $.update_statement,
            $.print_statement,
            $.assert_statement,
            $.panic_statement,
            $.return_statement,
            $.break_statement,
            $.continue_statement,
            $.expression_statement,
          ),
          choice(";", $._automatic_semicolon),
        ),
        $.if_statement,
        $.while_statement,
        $.for_statement,
        $.match_expression,
      ),

    variable_declaration: ($) =>
      seq(
        field("mutability", choice("let", "var")),
        field("name", $.identifier),
        choice(
          seq($.type_annotation, optional(seq("=", field("initializer", $.expression)))),
          seq("=", field("initializer", $.expression)),
        ),
      ),

    type_annotation: ($) => seq(":", field("type", $.type)),

    assignment_statement: ($) =>
      seq(
        field("left", choice($.identifier, $.member_expression, $.index_expression)),
        field("operator", choice("=", "+=", "-=", "*=", "/=")),
        field("right", $.expression),
      ),

    update_statement: ($) =>
      seq(
        field("argument", choice($.identifier, $.member_expression, $.index_expression)),
        field("operator", choice("++", "--")),
      ),

    print_statement: ($) =>
      seq(
        field("function", alias("print", $.identifier)),
        "(",
        field("argument", $.expression),
        ")",
      ),

    assert_statement: ($) =>
      seq(
        field("function", alias("assert", $.identifier)),
        "(",
        field("condition", $.expression),
        ",",
        field("message", $.expression),
        ")",
      ),

    panic_statement: ($) =>
      seq(
        field("function", alias("panic", $.identifier)),
        "(",
        field("message", $.expression),
        ")",
      ),

    return_statement: ($) => seq("return", optional(field("value", $.expression))),

    expression_statement: ($) =>
      choice(
        $.invocation_expression,
        $.super_method_expression,
        $.safe_member_expression,
        $.cascade_expression,
      ),

    if_statement: ($) =>
      seq(
        "if",
        field("condition", $._condition_header),
        field("body", $.block),
        repeat(field("branch", $.alternative_branch)),
        optional(seq("else", field("alternative", $.block))),
      ),

    alternative_branch: ($) =>
      choice(
        seq(
          "elif",
          field("condition", $._condition_header),
          field("body", $.block),
        ),
        seq(
          "else",
          "if",
          field("condition", $._condition_header),
          field("body", $.block),
        ),
      ),

    while_statement: ($) =>
      seq(
        "while",
        field("condition", $._condition_header),
        field("body", $.block),
      ),

    _condition_header: ($) =>
      choice($.expression, $.conditional_binding, seq("(", $.conditional_binding, ")")),

    conditional_binding: ($) =>
      seq(
        optional(field("mutability", choice("let", "var"))),
        field("name", $.identifier),
        "=",
        field("source", $.expression),
      ),

    for_statement: ($) =>
      seq(
        "for",
        choice($._for_binding, seq("(", $._for_binding, ")")),
        field("body", $.block),
      ),

    _for_binding: ($) =>
      seq(
        optional(field("mutability", choice("let", "var"))),
        field("name", $.identifier),
        "in",
        field("iterable", choice($.integer_range, $.expression)),
      ),

    integer_range: ($) =>
      choice(
        seq(
          field("start", $.expression),
          field("operator", "..."),
          field("end", $.expression),
        ),
        seq(
          "range",
          "(",
          field("start", $.expression),
          ",",
          field("end", $.expression),
          ")",
        ),
      ),

    break_statement: (_) => "break",

    continue_statement: (_) => "continue",

    expression: ($) =>
      choice(
        $.binary_expression,
        $.unary_expression,
        $.borrow_expression,
        $.conversion_expression,
        $.lambda_expression,
        $.match_expression,
        $.invocation_expression,
        $.super_method_expression,
        $.cascade_expression,
        $.sequence_literal,
        $.member_expression,
        $.safe_member_expression,
        $.index_expression,
        $.slice_expression,
        $.parenthesized_expression,
        $.string_literal,
        $.float_literal,
        $.integer_literal,
        $.boolean_literal,
        $.null_literal,
        $.self_expression,
        $.identifier,
      ),

    match_expression: ($) =>
      seq(
        "match",
        field("subject", $.expression),
        "{",
        repeat1($.match_branch),
        "}",
      ),

    match_branch: ($) =>
      seq(
        choice(
          seq(
            field("variant", $.identifier),
            optional(field("bindings", $.match_binding_list)),
          ),
          field("default", "else"),
        ),
        "=>",
        field(
          "body",
          choice(
            seq($.block, optional(choice(";", $._automatic_semicolon))),
            seq($.expression, choice(";", $._automatic_semicolon)),
          ),
        ),
      ),

    match_binding_list: ($) =>
      seq("(", $.match_binding, repeat(seq(",", $.match_binding)), ")"),

    match_binding: ($) =>
      seq(
        optional(field("mutability", choice("let", "var"))),
        field("name", $.identifier),
      ),

    lambda_expression: ($) =>
      seq(
        "func",
        $.parameter_list,
        optional(field("return_type", choice($.void_type, $.type))),
        field("body", $.block),
      ),

    super_method_expression: ($) =>
      seq(
        field("super", "super"),
        ".",
        field("method", $.identifier),
        field("arguments", $.argument_list),
      ),

    cascade_expression: ($) =>
      prec.left(
        PREC.member,
        seq(
          field("receiver", $._cascade_receiver),
          choice(
            repeat1($.cascade_operation),
            seq(
              repeat($.cascade_operation),
              alias($.cascade_method_operation, $.cascade_operation),
              repeat1($.cascade_terminal_operation),
            ),
          ),
        ),
      ),

    _cascade_receiver: ($) =>
      choice(
        $.identifier,
        $.self_expression,
        $.invocation_expression,
        $.member_expression,
        $.safe_member_expression,
        $.index_expression,
        $.slice_expression,
        $.sequence_literal,
        $.string_literal,
        $.float_literal,
        $.integer_literal,
        $.boolean_literal,
        $.parenthesized_expression,
        $.lambda_expression,
      ),

    cascade_operation: ($) =>
      seq(
        field("operator", ".."),
        choice($.cascade_method_call, $.cascade_field_assignment),
      ),

    cascade_method_operation: ($) =>
      seq(field("operator", ".."), $.cascade_method_call),

    cascade_terminal_operation: ($) =>
      choice(
        seq(".", field("field", $.identifier)),
        seq(
          ".",
          field("method", $.identifier),
          "(",
          optional(seq($.expression, repeat(seq(",", $.expression)))),
          ")",
        ),
      ),

    cascade_method_call: ($) =>
      seq(
        field("method", $.identifier),
        "(",
        optional(seq($.expression, repeat(seq(",", $.expression)))),
        ")",
      ),

    cascade_field_assignment: ($) =>
      seq(
        field("field", $.identifier),
        "=",
        field("value", $._cascade_assignment_value),
      ),

    _cascade_assignment_value: ($) =>
      choice(
        alias($.cascade_binary_expression, $.binary_expression),
        alias($.cascade_unary_expression, $.unary_expression),
        alias($.cascade_borrow_expression, $.borrow_expression),
        alias($.cascade_conversion_expression, $.conversion_expression),
        $.invocation_expression,
        $.sequence_literal,
        $.member_expression,
        $.index_expression,
        $.slice_expression,
        $.parenthesized_expression,
        $.string_literal,
        $.float_literal,
        $.integer_literal,
        $.boolean_literal,
        $.self_expression,
        $.identifier,
      ),

    cascade_binary_expression: ($) =>
      choice(
        prec.left(
          PREC.logicalOr,
          seq(
            field("left", $._cascade_assignment_value),
            field("operator", "||"),
            field("right", $._cascade_assignment_value),
          ),
        ),
        prec.left(
          PREC.logicalAnd,
          seq(
            field("left", $._cascade_assignment_value),
            field("operator", "&&"),
            field("right", $._cascade_assignment_value),
          ),
        ),
        prec.left(
          PREC.equality,
          seq(
            field("left", $._cascade_assignment_value),
            field("operator", choice("==", "!=")),
            field("right", $._cascade_assignment_value),
          ),
        ),
        prec.left(
          PREC.comparison,
          seq(
            field("left", $._cascade_assignment_value),
            field("operator", choice("<", "<=", ">", ">=")),
            field("right", $._cascade_assignment_value),
          ),
        ),
        prec.left(
          PREC.bitXor,
          seq(
            field("left", $._cascade_assignment_value),
            field("operator", "^"),
            field("right", $._cascade_assignment_value),
          ),
        ),
        prec.left(
          PREC.bitAnd,
          seq(
            field("left", $._cascade_assignment_value),
            field("operator", "&"),
            field("right", $._cascade_assignment_value),
          ),
        ),
        prec.left(
          PREC.shift,
          seq(
            field("left", $._cascade_assignment_value),
            field("operator", choice("<<", ">>")),
            field("right", $._cascade_assignment_value),
          ),
        ),
        prec.left(
          PREC.additive,
          seq(
            field("left", $._cascade_assignment_value),
            field("operator", choice("+", "-")),
            field("right", $._cascade_assignment_value),
          ),
        ),
        prec.left(
          PREC.multiplicative,
          seq(
            field("left", $._cascade_assignment_value),
            field("operator", choice("*", "/", "%")),
            field("right", $._cascade_assignment_value),
          ),
        ),
      ),

    cascade_unary_expression: ($) =>
      prec(
        PREC.unary,
        seq(
          field("operator", choice("!", "-")),
          field("operand", $._cascade_assignment_value),
        ),
      ),

    cascade_borrow_expression: ($) =>
      prec(
        PREC.unary,
        seq(field("operator", "&"), field("operand", $._cascade_assignment_value)),
      ),

    cascade_conversion_expression: ($) =>
      prec.left(
        PREC.conversion,
        seq(field("value", $._cascade_assignment_value), "as", field("type", $.type)),
      ),

    sequence_literal: ($) =>
      seq("[", optional(seq($.expression, repeat(seq(",", $.expression)), optional(","))), "]"),

    field_initializer: ($) =>
      seq(field("name", $.identifier), ":", field("value", $.expression)),

    member_expression: ($) =>
      prec.left(
        PREC.member,
        seq(
          field(
            "object",
            choice(
              $.identifier,
              $.generic_type,
              $.self_expression,
              $.invocation_expression,
              $.member_expression,
              $.safe_member_expression,
              $.index_expression,
              $.slice_expression,
              $.sequence_literal,
              $.string_literal,
              $.float_literal,
              $.integer_literal,
              $.boolean_literal,
              $.parenthesized_expression,
            ),
          ),
          ".",
          field("field", $.identifier),
        ),
      ),

    safe_member_expression: ($) =>
      prec.left(
        PREC.member,
        seq(
          field(
            "object",
            choice(
              $.identifier,
              $.self_expression,
              $.invocation_expression,
              $.member_expression,
              $.safe_member_expression,
              $.index_expression,
              $.slice_expression,
              $.sequence_literal,
              $.string_literal,
              $.float_literal,
              $.integer_literal,
              $.boolean_literal,
              $.null_literal,
              $.parenthesized_expression,
            ),
          ),
          "?.",
          field("field", $.identifier),
        ),
      ),

    invocation_expression: ($) =>
      seq(
        field(
          "target",
          choice(
            $.identifier,
            $.qualified_name,
            $.generic_type,
            $.parenthesized_expression,
            $.lambda_expression,
            $.member_expression,
            $.safe_member_expression,
            $.index_expression,
          ),
        ),
        "(",
        optional(
          choice(
            seq($.expression, repeat(seq(",", $.expression))),
            seq($.field_initializer, repeat(seq(",", $.field_initializer)), optional(",")),
          ),
        ),
        ")",
      ),

    index_expression: ($) =>
      prec.left(
        PREC.member,
        seq(
          field(
            "object",
            choice(
              $.identifier,
              $.self_expression,
              $.invocation_expression,
              $.member_expression,
              $.index_expression,
              $.slice_expression,
              $.sequence_literal,
              $.string_literal,
              $.float_literal,
              $.integer_literal,
              $.boolean_literal,
              $.parenthesized_expression,
            ),
          ),
          "[",
          field("index", $.expression),
          "]",
        ),
      ),

    slice_expression: ($) =>
      prec.left(
        PREC.member,
        seq(
          field(
            "object",
            choice(
              $.identifier,
              $.self_expression,
              $.invocation_expression,
              $.member_expression,
              $.index_expression,
              $.slice_expression,
              $.sequence_literal,
              $.string_literal,
              $.float_literal,
              $.integer_literal,
              $.boolean_literal,
              $.parenthesized_expression,
            ),
          ),
          "[",
          field("start", $.expression),
          ":",
          field("end", $.expression),
          "]",
        ),
      ),

    binary_expression: ($) =>
      choice(
        prec.left(
          PREC.logicalOr,
          seq(
            field("left", $.expression),
            field("operator", "||"),
            field("right", $.expression),
          ),
        ),
        prec.left(
          PREC.logicalAnd,
          seq(
            field("left", $.expression),
            field("operator", "&&"),
            field("right", $.expression),
          ),
        ),
        prec.left(
          PREC.equality,
          seq(
            field("left", $.expression),
            field("operator", choice("==", "!=")),
            field("right", $.expression),
          ),
        ),
        prec.left(
          PREC.comparison,
          seq(
            field("left", $.expression),
            field("operator", choice("<", "<=", ">", ">=")),
            field("right", $.expression),
          ),
        ),
        prec.left(
          PREC.bitXor,
          seq(
            field("left", $.expression),
            field("operator", "^"),
            field("right", $.expression),
          ),
        ),
        prec.left(
          PREC.bitAnd,
          seq(
            field("left", $.expression),
            field("operator", "&"),
            field("right", $.expression),
          ),
        ),
        prec.left(
          PREC.shift,
          seq(
            field("left", $.expression),
            field("operator", choice("<<", ">>")),
            field("right", $.expression),
          ),
        ),
        prec.left(
          PREC.additive,
          seq(
            field("left", $.expression),
            field("operator", choice("+", "-")),
            field("right", $.expression),
          ),
        ),
        prec.left(
          PREC.multiplicative,
          seq(
            field("left", $.expression),
            field("operator", choice("*", "/", "%")),
            field("right", $.expression),
          ),
        ),
      ),

    unary_expression: ($) =>
      prec(PREC.unary, seq(field("operator", choice("!", "-")), field("operand", $.expression))),

    borrow_expression: ($) => prec(PREC.unary, seq(field("operator", "&"), field("operand", $.expression))),

    conversion_expression: ($) =>
      prec.left(
        PREC.conversion,
        seq(field("value", $.expression), "as", field("type", $.type)),
      ),

    parenthesized_expression: ($) => seq("(", $.expression, ")"),

    string_literal: ($) =>
      seq('"', repeat(choice($.escape_sequence, /[^"\\\n\r]+/)), '"'),

    escape_sequence: (_) =>
      token(choice(/\\["\\nrt0]/, /\\u\{[0-9a-fA-F]{1,6}\}/)),
    integer_literal: (_) =>
      choice(
        /0[bB][01](?:_?[01])*/,
        /0[oO][0-7](?:_?[0-7])*/,
        /0[xX][0-9a-fA-F](?:_?[0-9a-fA-F])*/,
        /\d(?:_?\d)*/,
      ),
    float_literal: (_) =>
      choice(
        /\d(?:_?\d)*\.\d(?:_?\d)*(?:[eE][+-]?\d(?:_?\d)*)?/,
        /\d(?:_?\d)*[eE][+-]?\d(?:_?\d)*/,
      ),
    boolean_literal: (_) => choice("true", "false"),
    null_literal: (_) => "null",
    self_expression: (_) => "self",
    identifier: (_) => /[A-Za-z_][A-Za-z0-9_]*/,
    comment: (_) => token(seq("//", /[^\n]*/)),
  },
});
