(* Lambda variables *)

(*$Lvars: NAME LVARS*)

functor Lvars(structure Name : NAME) : LVARS =
  struct

    (* Lambda variables are based on names which may be `matched'. In
     * particular, if two lambda variables, lv1 and lv2, are
     * successfully matched, eq(lv1,lv2) = true. This may affect the
     * canonical ordering of lambda variables. *)

    (* For pattern-mathing, we declare a datatype for
     * compiler-supported primitives and a function 
     * primitive: lvar -> primitive Option *)

    datatype primitive = PLUS_INT | MINUS_INT | MUL_INT | DIV_INT | NEG_INT | ABS_INT
                       | LESS_INT | LESSEQ_INT | GREATER_INT | GREATEREQ_INT
                       | PLUS_FLOAT | MINUS_FLOAT | MUL_FLOAT | DIV_FLOAT | NEG_FLOAT | ABS_FLOAT
                       | LESS_FLOAT | LESSEQ_FLOAT | GREATER_FLOAT | GREATEREQ_FLOAT

    type name = Name.name

    type lvar = {name : name,
		 str : string,
		 free : bool ref,
		 inserted : bool ref,
		 use : int ref,
		 prim : primitive Option}

    fun new_named_lvar(str : string) : lvar = {name=Name.new(),
					       str=str,
					       free=ref false,
					       inserted=ref false,
					       use=ref 0,
					       prim=None}

    fun newLvar() : lvar = new_named_lvar ""

    fun new_prim(str,prim) : lvar = {name=Name.new(),
				     str=str,
				     free=ref false,
				     inserted=ref false,
				     use=ref 0,
				     prim=Some prim}


    fun pr_lvar ({str="",name,...} : lvar) : string = "v" ^ Int.string (Name.key name)
      | pr_lvar {str,...} = str

    fun pr_lvar' ({str="",name,...} : lvar) : string = "v_" ^ Int.string (Name.key name)
      | pr_lvar' {str,name,...} = str ^ "_" ^ Int.string (Name.key name)

    fun name ({name,...} : lvar) : name = name

    fun key lv = Name.key (name lv)

    fun leq(lv1,lv2) = key lv1 <= key lv2
    fun lt(lv1,lv2) = key lv1 < key lv2
    fun eq(lv1,lv2) = key lv1 = key lv2

    fun usage ({use,...} : lvar) = use
    fun reset_use lv = usage lv := 0
    fun incr_use lv = usage lv := (!(usage lv) + 1)
    fun decr_use lv = usage lv := (!(usage lv) - 1)
    fun zero_use lv = !(usage lv) = 0
    fun one_use lv = !(usage lv) = 1

    fun match(lv1,lv2) = Name.match(name lv1,name lv2)

    (* ------------------------------------ 
     * Compiler-supported primitives
     * ------------------------------------ *)

    val plus_int_lvar: lvar = new_prim("plus_int", PLUS_INT)         (* integer operations *)
    val minus_int_lvar: lvar = new_prim("minus_int", MINUS_INT)
    val mul_int_lvar: lvar = new_prim("mul_int", MUL_INT)
    val div_int_lvar: lvar = new_prim("div_int", DIV_INT)
    val negint_lvar: lvar = new_prim("neg_int", NEG_INT)
    val absint_lvar: lvar = new_prim("abs_int", ABS_INT)
    val less_int_lvar: lvar = new_prim("less_int", LESS_INT)
    val lesseq_int_lvar: lvar = new_prim("lesseq_int", LESSEQ_INT)
    val greater_int_lvar: lvar = new_prim("greater_int", GREATER_INT)
    val greatereq_int_lvar: lvar = new_prim("greatereq_int", GREATEREQ_INT)

    val plus_float_lvar: lvar = new_prim("plus_float", PLUS_FLOAT)         (* real operations *)
    val minus_float_lvar: lvar = new_prim("minus_float", MINUS_FLOAT)
    val mul_float_lvar: lvar = new_prim("mul_float", MUL_FLOAT)
    val div_float_lvar: lvar = new_prim("div_float", DIV_FLOAT)
    val negfloat_lvar: lvar = new_prim("neg_float", NEG_FLOAT)
    val absfloat_lvar: lvar = new_prim("abs_float", ABS_FLOAT)
    val less_float_lvar: lvar = new_prim("less_float", LESS_FLOAT)
    val lesseq_float_lvar: lvar = new_prim("lesseq_float", LESSEQ_FLOAT)
    val greater_float_lvar: lvar = new_prim("greater_float", GREATER_FLOAT)
    val greatereq_float_lvar: lvar = new_prim("greatereq_float", GREATEREQ_FLOAT)

    fun primitive ({prim,...}: lvar) : primitive Option = prim


    (* ------------------------------------ 
     * Non-compiler-supported primitives;
     *    these should be replaced by
     *    appropriate ccalls, later.
     * ------------------------------------ *)

    val floor_lvar: lvar = new_named_lvar "floor"       (* real operations *)
    val real_lvar: lvar = new_named_lvar "real"
    val sqrt_lvar: lvar = new_named_lvar "sqrt"
    val sin_lvar: lvar = new_named_lvar "sin"
    val cos_lvar: lvar = new_named_lvar "cos"
    val arctan_lvar: lvar = new_named_lvar "arctan"
    val exp_lvar: lvar = new_named_lvar "exp"
    val ln_lvar: lvar = new_named_lvar "ln"
 
    val open_in_lvar: lvar = new_named_lvar "open_in"           (* streams *)
    val open_out_lvar: lvar = new_named_lvar "open_out"
    val input_lvar: lvar = new_named_lvar "input"
    val lookahead_lvar: lvar = new_named_lvar "lookahead"
    val close_in_lvar: lvar = new_named_lvar "close_in"
    val end_of_stream_lvar: lvar = new_named_lvar "end_of_stream"
    val output_lvar: lvar = new_named_lvar "output_lvar"
    val close_out_lvar: lvar = new_named_lvar "close_out"
    val flush_out_lvar: lvar = new_named_lvar "flush_out"

    val chr_lvar: lvar = new_named_lvar "chr"                  (* strings *)
    val ord_lvar: lvar = new_named_lvar "ord"
    val size_lvar: lvar = new_named_lvar "size"
    val explode_lvar: lvar = new_named_lvar "explode"
    val implode_lvar: lvar = new_named_lvar "implode"

    val mod_int_lvar: lvar = new_named_lvar "mod"         (* others *)
    val use_lvar: lvar = new_named_lvar "use"
    val lvar_STD_IN: lvar = new_named_lvar "std_in"     (* the `commit' function is called below, *)
    val lvar_STD_OUT: lvar = new_named_lvar "std_out"   (* when all initial lvars are built... *)

    fun is_free ({free,...} : lvar) = free
    fun is_inserted ({inserted,...} : lvar) = inserted
  end;


(*$Lvarset : LVARS LVARSET *)

(***********************************************************************
  Applicative representation of finite sets of naturals, 1993-01-03
  sestoft@dina.kvl.dk
***********************************************************************)

functor Lvarset(structure Lvars : LVARS) : LVARSET = 
struct 
    type lvar = Lvars.lvar

    datatype lvarset = 
	LF 
      | BR of lvar Option * lvarset * lvarset

    fun sing (0,lvar) = BR(Some lvar, LF, LF)
      | sing (n,lvar) = if Bits.andb(n,1) <> 0 then
	                BR(None, sing(Bits.rshift(n,1),lvar), LF)
		 else
		     BR(None, LF, sing(Bits.rshift(n,1) - 1, lvar))

    fun singleton lvar = sing (Lvars.key lvar,lvar)
	
    fun cardinality LF             = 0
      | cardinality (BR(b, t1, t2)) = 
          case b of Some _ => 1 + cardinality t1 + cardinality t2
          | None => cardinality t1 + cardinality t2

    fun mkBR (None, LF, LF) = LF
      | mkBR (b, t1, t2) = BR(b, t1, t2)
	
    infix orElse
    fun _ orElse (b2 as Some _) = b2
      | (b1 as Some _) orElse _ = b1
      | _ orElse _ = None

    fun union (LF, ns2) = ns2
      | union (ns1, LF) = ns1
      | union (BR(b1, t11, t12), BR(b2, t21, t22)) =
	BR(b1 orElse b2, union(t11, t21), union(t12, t22))
	
    fun add (set,lvar) = union(set, singleton lvar)

    infix andAlso
    fun (Some _) andAlso (b2 as Some _) = b2
      | _ andAlso _ = None

    fun intersection (LF, ns2) = LF
      | intersection (ns1, LF) = LF
      | intersection (BR(b1, t11, t12), BR(b2, t21, t22)) =
	mkBR(b1 andAlso b2, intersection(t11, t21), intersection(t12, t22))
	

    fun difference (LF, ns2) = LF
      | difference (ns1, LF) = ns1
      | difference (BR(b1, t11, t12), BR(Some _, t21, t22)) =
        	mkBR(None, difference(t11, t21), difference(t12, t22))
      | difference (BR(b1, t11, t12), BR(None, t21, t22)) =
          	mkBR(b1, difference(t11, t21), difference(t12, t22))
		  
    fun delete (is, i) = difference(is, singleton i)

    fun present(Some _) = true
      | present None = false

    fun disjoint (LF, ns2) = true
      | disjoint (ns1, LF) = true
      | disjoint (BR(b1, t11, t12), BR(b2, t21, t22)) =
	not (present b1 andalso present b2) 
	andalso disjoint(t11, t21) 
	andalso disjoint (t12, t22)  

(*  fun member (i, is) = not(disjoint(is, singleton i)) *)

    fun member (lvar, is) = 
	let fun mem (_, LF)             = false
	      | mem (0, BR(b, _, _))     = (case b of Some _ => true | _ => false)
	      | mem (n, BR(_, ns1, ns2)) =
	        if Bits.andb(n,1) <> 0 then
	             mem(Bits.rshift(n,1), ns1)
		 else
		     mem(Bits.rshift(n,1) - 1, ns2)
	in mem(Lvars.key lvar, is) end

    fun lvarsetof []      = LF
      | lvarsetof (x::xs) = add(lvarsetof xs, x)

    fun foldset f (e, t) =
	let fun sl (n, d, LF, a)                 = a
	      | sl (n, d, BR(b, LF, LF), a) = 
                (case b of Some lvar => f(a,lvar) | _ => a)
	      | sl (n, d, BR(b, t1,    LF), a) = 
		sl(n+d, 2*d, t1,(case b of Some lvar => f(a,lvar) | _ => a) )
	      | sl (n, d, BR(b, t1,    t2), a)    = 
		sl(n+d, 2*d, t1, 
		   sl(n+2*d, 2*d, t2, (case b of Some lvar => f(a,lvar) | _ => a)))
	in sl(0, 1, t, e) end

    fun mapset f t = foldset (fn (a,i) => f i :: a) ([], t)

    fun members t = foldset (fn (a,i) => i :: a) ([], t)

    fun findLvar (pred: lvar -> '_a Option) lvarset = 
      let exception Found of (lvar * '_a)Option
          fun search LF = ()
            | search (BR(Some lvar, set1, set2)) =
               (case pred lvar of
                  Some x => raise Found(Some(lvar,x))
                | None => (search set1; search set2)
               )
            | search (BR(None, set1, set2)) = (search set1; search set2)
      in
        (search lvarset; None) handle Found result => result
      end
                    
  val empty = LF                

end
