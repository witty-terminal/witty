#include <fontconfig/fontconfig.h>
#include <stdint.h>

// FcValue contains a C union. Keeping that union on the C side avoids
// depending on V's representation of imported C unions while still exposing
// the complete value API.
typedef struct vt_fontconfig_value {
	int32_t type;
	int32_t integer_value;
	double double_value;
	const char *string_value;
	int32_t bool_value;
	const void *pointer_value;
} vt_fontconfig_value;

static void vt_fontconfig_value_from_fc(FcValue value,
		vt_fontconfig_value *out) {
	out->type = value.type;
	out->integer_value = 0;
	out->double_value = 0;
	out->string_value = 0;
	out->bool_value = 0;
	out->pointer_value = 0;

	switch (value.type) {
	case FcTypeInteger: out->integer_value = value.u.i; break;
	case FcTypeDouble: out->double_value = value.u.d; break;
	case FcTypeString: out->string_value = (const char *)value.u.s; break;
	case FcTypeBool: out->bool_value = value.u.b; break;
	case FcTypeMatrix: out->pointer_value = value.u.m; break;
	case FcTypeCharSet: out->pointer_value = value.u.c; break;
	case FcTypeFTFace: out->pointer_value = value.u.f; break;
	case FcTypeLangSet: out->pointer_value = value.u.l; break;
	case FcTypeRange: out->pointer_value = value.u.r; break;
	case FcTypeUnknown:
	case FcTypeVoid:
	default: break;
	}
}

static int vt_fontconfig_pattern_add(void *pattern, const char *object,
		const vt_fontconfig_value *value, int append) {
	FcValue fc_value;
	fc_value.type = (FcType)value->type;
	switch (fc_value.type) {
	case FcTypeInteger: fc_value.u.i = value->integer_value; break;
	case FcTypeDouble: fc_value.u.d = value->double_value; break;
	case FcTypeString: fc_value.u.s = (const FcChar8 *)value->string_value; break;
	case FcTypeBool: fc_value.u.b = value->bool_value; break;
	case FcTypeMatrix: fc_value.u.m = (const FcMatrix *)value->pointer_value; break;
	case FcTypeCharSet: fc_value.u.c = (const FcCharSet *)value->pointer_value; break;
	case FcTypeFTFace: fc_value.u.f = (void *)value->pointer_value; break;
	case FcTypeLangSet: fc_value.u.l = (const FcLangSet *)value->pointer_value; break;
	case FcTypeRange: fc_value.u.r = (const FcRange *)value->pointer_value; break;
	case FcTypeUnknown:
	case FcTypeVoid:
	default: fc_value.u.f = 0; break;
	}
	return FcPatternAdd((FcPattern *)pattern, object, fc_value,
		append ? FcTrue : FcFalse);
}

static int vt_fontconfig_pattern_get(void *pattern, const char *object,
		int id, vt_fontconfig_value *out) {
	FcValue value;
	FcResult result = FcPatternGet((FcPattern *)pattern, object, id, &value);
	if (result == FcResultMatch) vt_fontconfig_value_from_fc(value, out);
	return result;
}

static int vt_fontconfig_pattern_iter_get_value(void *pattern, void *iter,
		int id, vt_fontconfig_value *out, int *binding) {
	FcValue value;
	FcValueBinding fc_binding;
	FcResult result = FcPatternIterGetValue((FcPattern *)pattern,
		(FcPatternIter *)iter, id, &value, &fc_binding);
	*binding = fc_binding;
	vt_fontconfig_value_from_fc(value, out);
	return result;
}

// Read the `nfont` and `fonts` fields out of the opaque FcFontSet so that
// the V side doesn't have to mirror the C struct layout.
static int vt_fontconfig_fontset_nfont(void *fs) {
	if (!fs) return 0;
	return ((FcFontSet *)fs)->nfont;
}

static void *vt_fontconfig_fontset_font(void *fs, int idx) {
	if (!fs) return 0;
	FcFontSet *set = (FcFontSet *)fs;
	if (idx < 0 || idx >= set->nfont) return 0;
	return (void *)set->fonts[idx];
}
