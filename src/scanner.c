#include <stdbool.h>
#include <stddef.h>
#include <tree_sitter/parser.h>

enum TokenType {
    AUTOMATIC_SEMICOLON,
};

void* tree_sitter_silex_external_scanner_create(void) {
    return NULL;
}

void tree_sitter_silex_external_scanner_destroy(void* payload) {
    (void)payload;
}

unsigned tree_sitter_silex_external_scanner_serialize(void* payload, char* buffer) {
    (void)payload;
    (void)buffer;
    return 0;
}

void tree_sitter_silex_external_scanner_deserialize(
    void* payload,
    const char* buffer,
    unsigned length
) {
    (void)payload;
    (void)buffer;
    (void)length;
}

bool tree_sitter_silex_external_scanner_scan(
    void* payload,
    TSLexer* lexer,
    const bool* valid_symbols
) {
    (void)payload;
    if (!valid_symbols[AUTOMATIC_SEMICOLON]) return false;

    lexer->mark_end(lexer);
    while (lexer->lookahead == ' ' || lexer->lookahead == '\t' || lexer->lookahead == '\r') {
        lexer->advance(lexer, true);
    }

    if (lexer->lookahead == '\n') {
        lexer->advance(lexer, true);
        lexer->mark_end(lexer);
        lexer->result_symbol = AUTOMATIC_SEMICOLON;
        return true;
    }

    if (lexer->lookahead == '}' || lexer->eof(lexer)) {
        lexer->result_symbol = AUTOMATIC_SEMICOLON;
        return true;
    }

    return false;
}
