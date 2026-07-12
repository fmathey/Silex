const PREC = {
  logicalOr: 1,
  logicalAnd: 2,
  equality: 3,
  comparison: 4,
  additive: 5,
  multiplicative: 6,
  unary: 7,
};

module.exports = grammar({
  name: "silex",

  extras: ($) => [/\s/, $.comment],
  word: ($) => $.identifier,

  rules: {
    source_file: ($) => $.function_definition,

    function_definition: ($) =>
      seq(
        field("return_type", $.void_type),
        field("name", alias("main", $.identifier)),
        $.parameter_list,
        field("body", $.block),
      ),

    void_type: (_) => "void",
    builtin_type: (_) => choice("int", "bool", "string"),
    parameter_list: (_) => seq("(", ")"),

    block: ($) => seq("{", repeat($.statement), "}"),

    statement: ($) =>
      choice(
        $.variable_declaration,
        $.assignment_statement,
        $.print_statement,
        $.if_statement,
        $.while_statement,
      ),

    variable_declaration: ($) =>
      seq(
        field("mutability", choice("let", "var")),
        field("name", $.identifier),
        optional($.type_annotation),
        "=",
        field("initializer", $.expression),
        ";",
      ),

    type_annotation: ($) => seq(":", field("type", $.builtin_type)),

    assignment_statement: ($) =>
      seq(
        field("left", $.identifier),
        "=",
        field("right", $.expression),
        ";",
      ),

    print_statement: ($) =>
      seq(
        field("function", alias("print", $.identifier)),
        "(",
        field("argument", $.expression),
        ")",
        ";",
      ),

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
        $.parenthesized_expression,
        $.string_literal,
        $.integer_literal,
        $.boolean_literal,
        $.identifier,
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
    identifier: (_) => /[A-Za-z_][A-Za-z0-9_]*/,
    comment: (_) => token(seq("//", /[^\n]*/)),
  },
});
