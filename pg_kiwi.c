/*
 * pg_kiwi.c - Korean full-text search parser using Kiwi morphological analyzer
 *
 * MIT License
 * Copyright (c) 2024-2026, pg_kiwi contributors
 */

#include "postgres.h"
#include "fmgr.h"
#include "miscadmin.h"
#include "utils/guc.h"
#include "storage/ipc.h"
#include "tsearch/ts_public.h"

#include <kiwi/capi.h>
#include <string.h>

PG_MODULE_MAGIC;

/* Token type IDs */
#define TOKEN_NOUN    1
#define TOKEN_VERB    2
#define TOKEN_ADJ     3
#define TOKEN_ADV     4
#define TOKEN_DET     5
#define TOKEN_NUMBER  6
#define TOKEN_FOREIGN 7
#define TOKEN_UNKNOWN 8
#define NUM_TOKEN_TYPES 8

/* GUC variables */
static char *kiwi_model_path = NULL;
static bool  kiwi_pos_filter = true;

/* Per-backend Kiwi handle (lazy singleton) */
static kiwi_h kiwi_handle = NULL;

/* Per-parse state */
typedef struct
{
	kiwi_res_h result;
	int        num_tokens;
	int        cur_token;
} KiwiParserState;

/* Forward declarations */
static void kiwi_cleanup(int code, Datum arg);
static void kiwi_model_path_assign(const char *newval, void *extra);
static void ensure_kiwi_initialized(void);
static int  map_pos_tag(const char *tag);

void _PG_init(void);

PG_FUNCTION_INFO_V1(kiwi_parser_start);
PG_FUNCTION_INFO_V1(kiwi_parser_gettoken);
PG_FUNCTION_INFO_V1(kiwi_parser_end);
PG_FUNCTION_INFO_V1(kiwi_parser_lextype);

/*
 * _PG_init - Register GUC variables and cleanup callback
 */
void
_PG_init(void)
{
	DefineCustomStringVariable(
		"pg_kiwi.model_path",
		"Path to Kiwi model directory.",
		NULL,
		&kiwi_model_path,
		"/usr/local/share/kiwi_model/models/cong/base",
		PGC_SIGHUP,
		0,
		NULL, kiwi_model_path_assign, NULL);

	DefineCustomBoolVariable(
		"pg_kiwi.pos_filter",
		"Filter out particles, endings, and symbols.",
		NULL,
		&kiwi_pos_filter,
		true,
		PGC_USERSET,
		0,
		NULL, NULL, NULL);

	on_proc_exit(kiwi_cleanup, 0);
}

/*
 * kiwi_cleanup - Release Kiwi handle on backend exit
 */
static void
kiwi_cleanup(int code, Datum arg)
{
	if (kiwi_handle)
	{
		kiwi_close(kiwi_handle);
		kiwi_handle = NULL;
	}
}

/*
 * kiwi_model_path_assign - Re-initialize Kiwi when model path changes via SIGHUP
 */
static void
kiwi_model_path_assign(const char *newval, void *extra)
{
	if (kiwi_handle)
	{
		kiwi_close(kiwi_handle);
		kiwi_handle = NULL;
	}
}

/*
 * ensure_kiwi_initialized - Lazy initialization of Kiwi model
 */
static void
ensure_kiwi_initialized(void)
{
	if (kiwi_handle)
		return;

	if (!kiwi_model_path || kiwi_model_path[0] == '\0')
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("pg_kiwi.model_path is not set")));

	kiwi_handle = kiwi_init(kiwi_model_path, 1, KIWI_BUILD_DEFAULT);
	if (!kiwi_handle)
	{
		const char *err = kiwi_error();
		ereport(ERROR,
				(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
				 errmsg("pg_kiwi: failed to initialize Kiwi model: %s",
						 err ? err : "unknown error"),
				 errhint("Check pg_kiwi.model_path (current: \"%s\").",
						 kiwi_model_path)));
	}
}

/*
 * map_pos_tag - Map Kiwi POS tag to parser token type
 *
 * Returns token type ID (1-8) for emitted tags, 0 for filtered tags.
 */
static int
map_pos_tag(const char *tag)
{
	if (!tag || !tag[0])
		return 0;

	switch (tag[0])
	{
		case 'N':
			/* NNG, NNP, NNB → noun */
			if (tag[1] == 'N' && (tag[2] == 'G' || tag[2] == 'P' || tag[2] == 'B'))
				return TOKEN_NOUN;
			/* NR (numeral), NP (pronoun) → noun */
			if (tag[1] == 'R' || tag[1] == 'P')
				return TOKEN_NOUN;
			break;

		case 'V':
			/* VA → adjective */
			if (tag[1] == 'A')
				return TOKEN_ADJ;
			/* VV, VX → verb */
			if (tag[1] == 'V' || tag[1] == 'X')
				return TOKEN_VERB;
			/* VCP, VCN → verb */
			if (tag[1] == 'C')
				return TOKEN_VERB;
			break;

		case 'M':
			/* MAG, MAJ → adverb */
			if (tag[1] == 'A')
				return TOKEN_ADV;
			/* MM → determiner */
			if (tag[1] == 'M')
				return TOKEN_DET;
			break;

		case 'S':
			/* SN → number */
			if (tag[1] == 'N')
				return TOKEN_NUMBER;
			/* SL (foreign), SH (hanja) → foreign */
			if (tag[1] == 'L' || tag[1] == 'H')
				return TOKEN_FOREIGN;
			/* SF, SP, SS, SE, SO, SW → filtered */
			break;

		case 'U':
			/* UN → unknown */
			if (tag[1] == 'N')
				return TOKEN_UNKNOWN;
			break;

		default:
			/* J* (particles), E* (endings), X* (affixes), IC → filtered */
			break;
	}

	return 0;
}

/*
 * kiwi_parser_start - Begin parsing: run Kiwi analysis on input text
 */
Datum
kiwi_parser_start(PG_FUNCTION_ARGS)
{
	char              *txt = (char *) PG_GETARG_POINTER(0);
	int                len = PG_GETARG_INT32(1);
	KiwiParserState   *state;
	char              *input;
	kiwi_analyze_option_t opt;

	ensure_kiwi_initialized();

	/* Null-terminate the input text */
	input = pnstrdup(txt, len);

	/* Analyze with Kiwi */
	memset(&opt, 0, sizeof(opt));
	opt.match_options = KIWI_MATCH_ALL_WITH_NORMALIZING;
	opt.dialect_cost = 3.0f;

	state = (KiwiParserState *) palloc0(sizeof(KiwiParserState));
	state->result = kiwi_analyze(kiwi_handle, input, 1, opt, NULL);

	pfree(input);

	if (!state->result)
	{
		const char *err = kiwi_error();
		pfree(state);
		ereport(ERROR,
				(errcode(ERRCODE_EXTERNAL_ROUTINE_EXCEPTION),
				 errmsg("pg_kiwi: kiwi_analyze() failed: %s",
						 err ? err : "unknown error")));
	}

	state->num_tokens = kiwi_res_word_num(state->result, 0);
	state->cur_token = 0;

	PG_RETURN_POINTER(state);
}

/*
 * kiwi_parser_gettoken - Return next token from analysis result
 *
 * Kiwi returns lemma forms (원형), not substrings of the original text.
 * The form pointers are internal to kiwi_res_h and freed by kiwi_res_close()
 * in end(). We copy each form into palloc'd memory via pnstrdup to avoid
 * use-after-free if PostgreSQL defers token consumption.
 */
Datum
kiwi_parser_gettoken(PG_FUNCTION_ARGS)
{
	KiwiParserState *state = (KiwiParserState *) PG_GETARG_POINTER(0);
	char           **token = (char **) PG_GETARG_POINTER(1);
	int             *toklen = (int *) PG_GETARG_POINTER(2);

	while (state->cur_token < state->num_tokens)
	{
		const char *form;
		const char *tag;
		int         type;
		int         idx = state->cur_token++;

		tag = kiwi_res_tag(state->result, 0, idx);
		type = map_pos_tag(tag);

		/* Skip filtered POS tags */
		if (kiwi_pos_filter && type == 0)
			continue;

		/* When filter is off, assign unknown to unmapped tags */
		if (type == 0)
			type = TOKEN_UNKNOWN;

		form = kiwi_res_form(state->result, 0, idx);
		if (!form || form[0] == '\0')
			continue;

		*toklen = strlen(form);
		*token = pnstrdup(form, *toklen);

		PG_RETURN_INT32(type);
	}

	/* No more tokens */
	PG_RETURN_INT32(0);
}

/*
 * kiwi_parser_end - Release analysis result and state
 */
Datum
kiwi_parser_end(PG_FUNCTION_ARGS)
{
	KiwiParserState *state = (KiwiParserState *) PG_GETARG_POINTER(0);

	if (state->result)
		kiwi_res_close(state->result);

	pfree(state);

	PG_RETURN_VOID();
}

/*
 * kiwi_parser_lextype - Return supported token types
 */
Datum
kiwi_parser_lextype(PG_FUNCTION_ARGS)
{
	LexDescr *descr = (LexDescr *) palloc0(sizeof(LexDescr) * (NUM_TOKEN_TYPES + 1));

	descr[0].lexid = TOKEN_NOUN;
	descr[0].alias = pstrdup("noun");
	descr[0].descr = pstrdup("Noun (NNG, NNP, NNB, NR, NP)");

	descr[1].lexid = TOKEN_VERB;
	descr[1].alias = pstrdup("verb");
	descr[1].descr = pstrdup("Verb (VV, VX, VCP, VCN)");

	descr[2].lexid = TOKEN_ADJ;
	descr[2].alias = pstrdup("adj");
	descr[2].descr = pstrdup("Adjective (VA)");

	descr[3].lexid = TOKEN_ADV;
	descr[3].alias = pstrdup("adv");
	descr[3].descr = pstrdup("Adverb (MAG, MAJ)");

	descr[4].lexid = TOKEN_DET;
	descr[4].alias = pstrdup("det");
	descr[4].descr = pstrdup("Determiner (MM)");

	descr[5].lexid = TOKEN_NUMBER;
	descr[5].alias = pstrdup("number");
	descr[5].descr = pstrdup("Number (SN)");

	descr[6].lexid = TOKEN_FOREIGN;
	descr[6].alias = pstrdup("foreign");
	descr[6].descr = pstrdup("Foreign/Hanja (SL, SH)");

	descr[7].lexid = TOKEN_UNKNOWN;
	descr[7].alias = pstrdup("unknown");
	descr[7].descr = pstrdup("Unknown (UN)");

	descr[8].lexid = 0;	/* terminator */

	PG_RETURN_POINTER(descr);
}
