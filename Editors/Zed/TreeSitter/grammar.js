const PREC = {
  logicalOr: 1,
  logicalAnd: 2,
  equality: 3,
  comparison: 4,
  additive: 5,
  multiplicative: 6,
  unary: 7,
  conversion: 8,
  member: 9,
};

module.exports = grammar({
  name: "silex",

  extras: ($) => [/\s/, $.comment],
  word: ($) => $.identifier,
  externals: ($) => [$._automatic_semicolon],

  rules: {
    source_file: ($) =>
      repeat(
        choice(
          $.import_declaration,
          $.use_declaration,
          $.structure_definition,
          $.function_definition,
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
        field("declaration", $.qualified_name),
        optional(seq("as", field("alias", $.identifier))),
        choice(";", $._automatic_semicolon),
      ),

    public_declaration: ($) =>
      seq(field("visibility", "pub"), choice($.structure_definition, $.function_definition)),

    module_path: ($) =>
      seq($.identifier, repeat(seq(".", $.identifier))),

    qualified_name: ($) =>
      seq($.identifier, repeat1(seq(".", $.identifier))),

    structure_definition: ($) =>
      seq(
        "struct",
        field("name", $.identifier),
        "{",
        repeat(choice($.structure_field, $.function_definition)),
        "}",
      ),

    structure_field: ($) =>
      seq(
        field("name", $.identifier),
        ":",
        field("type", $.type),
        optional(seq("=", field("default", $.expression))),
        choice(";", $._automatic_semicolon),
      ),

    function_definition: ($) =>
      seq(
        "func",
        field("name", $.identifier),
        $.parameter_list,
        optional(field("return_type", choice($.void_type, $.type))),
        field("body", $.block),
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
    named_type: ($) => alias(choice($.identifier, $.qualified_name), $.type_identifier),
    array_type: ($) =>
      seq(
        field("element", choice($.builtin_type, $.named_type)),
        repeat1(choice(seq("[", "]"), seq("[", field("length", $.integer_literal), "]"))),
      ),
    reference_type: ($) =>
      seq(field("target", choice($.array_type, $.builtin_type, $.named_type)), field("kind", choice("&", "@"))),
    type: ($) => choice($.reference_type, $.array_type, $.builtin_type, $.named_type),
    parameter_list: ($) =>
      seq("(", optional(seq($.parameter, repeat(seq(",", $.parameter)))), ")"),

    parameter: ($) =>
      seq(field("name", $.identifier), ":", field("type", $.type)),

    block: ($) => seq("{", repeat($.statement), "}"),

    statement: ($) =>
      choice(
        seq(
          choice(
            $.variable_declaration,
            $.assignment_statement,
            $.update_statement,
            $.print_statement,
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
        field("left", choice($.identifier, $.member_expression, $.index_expression, $.dereference_expression)),
        field("operator", choice("=", "+=", "-=", "*=", "/=")),
        field("right", $.expression),
      ),

    update_statement: ($) =>
      seq(
        field("argument", choice($.identifier, $.member_expression, $.index_expression, $.dereference_expression)),
        field("operator", choice("++", "--")),
      ),

    print_statement: ($) =>
      seq(
        field("function", alias("print", $.identifier)),
        "(",
        field("argument", $.expression),
        ")",
      ),

    return_statement: ($) => seq("return", optional(field("value", $.expression))),

    expression_statement: ($) =>
      choice($.call_expression, $.method_call_expression, $.cascade_expression),

    if_statement: ($) =>
      seq(
        "if",
        "(",
        field("condition", $.expression),
        ")",
        field("body", $.block),
        optional(seq("else", field("alternative", $.block))),
      ),

    while_statement: ($) =>
      seq(
        "while",
        "(",
        field("condition", $.expression),
        ")",
        field("body", $.block),
      ),

    for_statement: ($) =>
      seq(
        "for",
        "(",
        optional(field("mutability", "var")),
        field("name", $.identifier),
        "in",
        field("iterable", $.expression),
        ")",
        field("body", $.block),
      ),

    break_statement: (_) => "break",

    continue_statement: (_) => "continue",

    expression: ($) =>
      choice(
        $.binary_expression,
        $.unary_expression,
        $.dereference_expression,
        $.borrow_expression,
        $.copy_expression,
        $.move_expression,
        $.conversion_expression,
        $.call_expression,
        $.method_call_expression,
        $.cascade_expression,
        $.structure_initializer,
        $.sequence_literal,
        $.member_expression,
        $.index_expression,
        $.parenthesized_expression,
        $.string_literal,
        $.float_literal,
        $.integer_literal,
        $.boolean_literal,
        $.self_expression,
        $.identifier,
      ),

    cascade_expression: ($) =>
      prec.left(
        PREC.member,
        seq(
          field(
            "receiver",
            choice(
              $.identifier,
              $.self_expression,
              $.call_expression,
              $.structure_initializer,
              $.member_expression,
              $.index_expression,
              $.method_call_expression,
              $.sequence_literal,
              $.string_literal,
              $.float_literal,
              $.integer_literal,
              $.boolean_literal,
              $.parenthesized_expression,
            ),
          ),
          repeat1($.cascade_operation),
        ),
      ),

    cascade_operation: ($) =>
      seq(
        field("operator", ".."),
        choice($.cascade_method_call, $.cascade_field_assignment),
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
        alias($.cascade_dereference_expression, $.dereference_expression),
        alias($.cascade_borrow_expression, $.borrow_expression),
        alias($.cascade_conversion_expression, $.conversion_expression),
        $.copy_expression,
        $.move_expression,
        $.call_expression,
        $.method_call_expression,
        $.structure_initializer,
        $.sequence_literal,
        $.member_expression,
        $.index_expression,
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
            field("operator", choice("*", "/")),
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

    cascade_dereference_expression: ($) =>
      prec(
        PREC.unary,
        seq(field("operator", "*"), field("operand", $._cascade_assignment_value)),
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

    structure_initializer: ($) =>
      seq(
        field("type", choice($.identifier, $.qualified_name)),
        "{",
        optional(seq($.field_initializer, repeat(seq(",", $.field_initializer)), optional(","))),
        "}",
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
              $.self_expression,
              $.call_expression,
              $.structure_initializer,
              $.member_expression,
              $.index_expression,
              $.method_call_expression,
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

    call_expression: ($) =>
      seq(
        field("function", choice($.identifier, $.qualified_name)),
        "(",
        optional(seq($.expression, repeat(seq(",", $.expression)))),
        ")",
      ),

    method_call_expression: ($) =>
      prec.left(
        PREC.member,
        seq(
          field(
            "object",
            choice(
              $.identifier,
              $.self_expression,
              $.call_expression,
              $.structure_initializer,
              $.member_expression,
              $.index_expression,
              $.method_call_expression,
              $.sequence_literal,
              $.string_literal,
              $.float_literal,
              $.integer_literal,
              $.boolean_literal,
              $.parenthesized_expression,
            ),
          ),
          ".",
          field("method", $.identifier),
          "(",
          optional(seq($.expression, repeat(seq(",", $.expression)))),
          ")",
        ),
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
              $.call_expression,
              $.structure_initializer,
              $.member_expression,
              $.index_expression,
              $.method_call_expression,
              $.sequence_literal,
              $.string_literal,
              $.float_literal,
              $.integer_literal,
              $.boolean_literal,
              $.parenthesized_expression,
            ),
          ),
          "[",
          optional(field("from_end", "^")),
          field("index", $.expression),
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
            field("operator", choice("*", "/")),
            field("right", $.expression),
          ),
        ),
      ),

    unary_expression: ($) =>
      prec(PREC.unary, seq(field("operator", choice("!", "-")), field("operand", $.expression))),

    dereference_expression: ($) =>
      prec(PREC.unary, seq(field("operator", "*"), field("operand", $.expression))),

    borrow_expression: ($) => prec(PREC.unary, seq(field("operator", "&"), field("operand", $.expression))),

    copy_expression: ($) =>
      prec.right(
        PREC.unary,
        seq(
          "copy",
          field(
            "operand",
            choice(
              $.method_call_expression,
              $.call_expression,
              $.member_expression,
              $.index_expression,
              $.identifier,
            ),
          ),
        ),
      ),

    move_expression: ($) => prec(PREC.unary, seq("move", field("operand", $.identifier))),

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
    self_expression: (_) => "self",
    identifier: (_) => /[A-Za-z_][A-Za-z0-9_]*/,
    comment: (_) => token(seq("//", /[^\n]*/)),
  },
});
