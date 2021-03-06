
type elt =
  | OrigElt of string
  | Removed of string
  | Added of string
  | Esthet of esthet
  and esthet =
   | Comment of string
   | Newline
   | Space of string

(* helpers *)
val elts_of_any:
  elt_of_tok:('a -> elt) ->
  info_of_tok:('a -> Parse_info.info) -> 'a -> 
  elt list

(* debugging *)
val vof_elt: elt -> Ocaml.v

(* heuristics *)
val drop_esthet_between_removed: elt list -> elt list
val drop_whole_line_if_only_removed: elt list -> elt list

val debug: bool ref

(* main entry point *)
val string_of_toks_using_transfo:
 elts_of_tok:('a -> elt list) -> 
  'a list -> string
