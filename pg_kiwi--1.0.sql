\echo Use "CREATE EXTENSION pg_kiwi" to load this file. \quit

-- pg_kiwi: Korean full-text search parser using Kiwi morphological analyzer

-- Parser functions
CREATE FUNCTION kiwi_parser_start(internal, int4)
    RETURNS internal
    AS 'MODULE_PATHNAME'
    LANGUAGE C;

CREATE FUNCTION kiwi_parser_gettoken(internal, internal, internal)
    RETURNS internal
    AS 'MODULE_PATHNAME'
    LANGUAGE C;

CREATE FUNCTION kiwi_parser_end(internal)
    RETURNS void
    AS 'MODULE_PATHNAME'
    LANGUAGE C;

CREATE FUNCTION kiwi_parser_lextype(internal)
    RETURNS internal
    AS 'MODULE_PATHNAME'
    LANGUAGE C;

-- Register text search parser
CREATE TEXT SEARCH PARSER kiwi_parser (
    START    = kiwi_parser_start,
    GETTOKEN = kiwi_parser_gettoken,
    END      = kiwi_parser_end,
    LEXTYPES = kiwi_parser_lextype
);

COMMENT ON TEXT SEARCH PARSER kiwi_parser
    IS 'Korean morphological parser using Kiwi';

-- Create text search configuration
CREATE TEXT SEARCH CONFIGURATION korean (PARSER = kiwi_parser);

COMMENT ON TEXT SEARCH CONFIGURATION korean
    IS 'Korean full-text search configuration using Kiwi';

-- Map all token types to simple dictionary
ALTER TEXT SEARCH CONFIGURATION korean
    ADD MAPPING FOR noun, verb, adj, adv, det, number, "foreign", unknown
    WITH simple;
