const PREC = {
  logicalOr: 1,
  logicalAnd: 2,
  equality: 3,
  comparison: 4,
  additive: 5,
  multiplicative: 6,
  unary: 7,
  member: 8,
};

module.exports = grammar({
  name: "silex",

  extras: ($) => [/\s/, $.comment],
  word: ($) => $.identifier,
  externals: ($) => [$._automatic_semicolon],

  rules: {
    source_file: ($) => repeat(choice($.structure_definition, $.function_definition)),

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
        field("return_type", choice($.void_type, $.type)),
        field("body", $.block),
      ),

    void_type: (_) => "void",
    builtin_type: (_) => choice("int", "bool", "string"),
    named_type: ($) => alias($.identifier, $.type_identifier),
    type: ($) => choice($.builtin_type, $.named_type),
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
            $.expression_statement,
          ),
          choice(";", $._automatic_semicolon),
        ),
        $.if_statement,
        $.while_statement,
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
        field("left", choice($.identifier, $.member_expression)),
        field("operator", choice("=", "+=", "-=", "*=", "/=")),
        field("right", $.expression),
      ),

    update_statement: ($) =>
      seq(
        field("argument", choice($.identifier, $.member_expression)),
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

    expression_statement: ($) => choice($.call_expression, $.method_call_expression),

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

    expression: ($) =>
      choice(
        $.binary_expression,
        $.unary_expression,
        $.call_expression,
        $.method_call_expression,
        $.structure_initializer,
        $.member_expression,
        $.parenthesized_expression,
        $.string_literal,
        $.integer_literal,
        $.boolean_literal,
        $.self_expression,
        $.identifier,
      ),

    structure_initializer: ($) =>
      seq(
        field("type", $.identifier),
        "{",
        optional(seq($.field_initializer, repeat(seq(",", $.field_initializer)), optional(","))),
        "}",
      ),

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
              $.method_call_expression,
            ),
          ),
          ".",
          field("field", $.identifier),
        ),
      ),

    call_expression: ($) =>
      seq(
        field("function", $.identifier),
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
              $.method_call_expression,
            ),
          ),
          ".",
          field("method", $.identifier),
          "(",
          optional(seq($.expression, repeat(seq(",", $.expression)))),
          ")",
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
      prec(PREC.unary, seq(field("operator", "!"), field("operand", $.expression))),

    parenthesized_expression: ($) => seq("(", $.expression, ")"),

    string_literal: ($) =>
      seq('"', repeat(choice($.escape_sequence, /[^"\\\n\r]+/)), '"'),

    escape_sequence: (_) => token(seq("\\", /./)),
    integer_literal: (_) => /\d+/,
    boolean_literal: (_) => choice("true", "false"),
    self_expression: (_) => "self",
    identifier: (_) => /[A-Za-z_][A-Za-z0-9_]*/,
    comment: (_) => token(seq("//", /[^\n]*/)),
  },
});
