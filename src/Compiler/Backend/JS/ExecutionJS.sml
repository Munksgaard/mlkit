
structure ExecutionJS : EXECUTION =
  struct
    structure Compile = CompileJS
    structure TopdecGrammar = PostElabTopdecGrammar
    structure PP = PrettyPrint
    structure Labels = AddressLabels

    structure DecGrammar = TopdecGrammar.DecGrammar

    structure CompileBasis = CompileBasisJS

    val backend_name = "SmlToJs"
    val backend_longname = "SmlToJs - Standard ML to JavaScript Compiler"

    type CompileBasis = CompileBasis.CompileBasis
    type CEnv = CompilerEnv.CEnv
    type Env = CompilerEnv.ElabEnv
    type strdec = TopdecGrammar.strdec
    type strexp = TopdecGrammar.strexp
    type funid = TopdecGrammar.funid
    type strid = TopdecGrammar.strid
    type lab = string
    fun pr_lab s = s
    type linkinfo = {unsafe:bool,imports:lab list,exports:lab list}
    type target = Compile.target

    val dummy_label = "__DUMMYDUMMY"
    val code_label_of_linkinfo : linkinfo -> lab = fn _ => dummy_label

    fun imports_of_linkinfo (li: linkinfo) : lab list * lab list = 
        (#imports li,nil)
    fun exports_of_linkinfo (li: linkinfo) : lab list * lab list = 
        (#exports li,nil)

    fun unsafe_linkinfo (li: linkinfo) : bool =  #unsafe li

    (* Hook to be run before any compilation *)
    val preHook = Compile.preHook
	
    (* Hook to be run after all compilations (for one compilation unit) *)
    val postHook = Compile.postHook

    datatype res = CodeRes of CEnv * CompileBasis * target * linkinfo
                 | CEnvOnlyRes of CEnv
    fun compile fe (ce,CB,strdecs,vcg_file) =
      let val (cb,()) = CompileBasis.de_CompileBasis CB
      in
	case Compile.compile fe (ce, cb, strdecs)
	  of Compile.CEnvOnlyRes ce => CEnvOnlyRes ce
	   | Compile.CodeRes(ce,cb,target,safe) => 
	    let 
                val {imports,exports} = #2 target
		val linkinfo : linkinfo = {unsafe=not(safe),imports=imports,exports=exports}   
		val CB = CompileBasis.mk_CompileBasis(cb,())
	    in CodeRes(ce,CB,target,linkinfo)
	    end
      end
    val generate_link_code = NONE

    fun emit a = Compile.emit a

    val be_rigid = true

    val op ## = OS.Path.concat infix ##

    val get_jslibs = Flags.add_stringlist_entry 
      {long="javascript_library_paths",
       short=SOME "jslibs",
       menu=["Control","JavaScript library paths"],
       item=ref nil,
       desc="Use this option to add javascript library paths\n\
            \to the generated html and thereby allow for SML\n\
            \code to reference existing JavaScript libraries."}

    val js_path_compress = Flags.add_bool_entry 
	{long="js_path_compress", short=NONE, 
	 menu=["File","js path compress"],
	 item=ref false, neg=false, 
         desc= "Compress (make canonical) Javascript file path\n\
               \references in the resulting run.html file."}

    val js_path_prefix = Flags.add_string_entry 
        {long="js_path_prefix", short=NONE, menu=["File", "js path prefix"], 
         item=ref "",
         desc= "Prefix to add to each Javascript file path in the\n\
               \resulting run.html file."}

    fun link_files_with_runtime_system files run =
	let val html_file = run ^ ".html"
	    val os = TextIO.openOut html_file
            fun out s = TextIO.output(os,s)
            fun outJsFile f =
                let val f = js_path_prefix() ## f
                    val f = if js_path_compress() then OS.Path.mkCanonical f 
                            else f
                in out ("<script type=\"text/javascript\" src=\"" ^ f ^ "\"></script>\n")
                end
            val jslibs = get_jslibs()
            val files = jslibs @ files
	in 
	    (out ("<!-- JavaScript generated by " ^ backend_longname ^ " -->\n");
             out ("<!-- See http://www.itu.dk/people/mael/smltojs -->\n");
             outJsFile (!Flags.install_dir ## "prims.js");
	     app outJsFile files;
	     TextIO.closeOut os;
	     print("[Created file " ^ html_file ^ "]\n"))
	    handle X => (TextIO.closeOut os; raise X)
	end

    fun mlbdir() = "MLB" ## "Js"

    val pu_linkinfo =
        let val pu_sList = Pickle.listGen Pickle.string
        in
	  Pickle.convert (fn (is,es,b) => {imports=is,exports=es,unsafe=b},
			  fn {imports=is,exports=es,unsafe=b} => (is,es,b))
	                 (Pickle.tup3Gen(pu_sList,pu_sList,Pickle.bool))
        end
  end

