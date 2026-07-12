function commaSeparated(rule) {
  return seq(rule, repeat(seq(",", rule)));
}

module.exports = grammar({
  name: "silex",

  extras: ($) => [/\s/, $.comment],
  word: ($) => $.identifier,

  rules: {
    source_file: ($) => repeat($.function_definition),

    function_definition: ($) =>
      seq(
        field("return_type", $.builtin_type),
        field("name", $.identifier),
        $.parameter_list,
        field("body", $.block),
      ),

    builtin_type: (_) => choice("void", "bool", "int", "float", "string"),

    parameter_list: ($) =>
      seq("(", optional(commaSeparated($.parameter)), ")"),

    parameter: ($) =>
      seq(field("type", $.builtin_type), field("name", $.identifier)),

    block: ($) => seq("{", repeat($._statement), "}"),

    _statement: ($) => choice($.expression_statement, $.return_statement),

    expression_statement: ($) => seq($.expression, ";"),

    return_statement: ($) => seq("return", optional($.expression), ";"),

    expression: ($) =>
      choice(
        $.call_expression,
        $.string_literal,
        $.boolean_literal,
        $.number_literal,
        $.identifier,
      ),

    call_expression: ($) =>
      seq(
        field("function", $.identifier),
        "(",
        optional(commaSeparated($.expression)),
        ")",
      ),

    string_literal: ($) =>
      seq('"', repeat(choice($.escape_sequence, /[^"\\\n\r]+/)), '"'),

    escape_sequence: (_) => token(seq("\\", /./)),
    boolean_literal: (_) => choice("true", "false"),
    number_literal: (_) => token(choice(/\d+\.\d+/, /\d+/)),
    identifier: (_) => /[A-Za-z_][A-Za-z0-9_]*/,
    comment: (_) => token(seq("//", /[^\n]*/)),
  },
});
