signature SCS_DATE =
  sig
    exception ScsDate of string

    type day = int
    type mth = int
    type year = int
    type hour = int
    type sec = int

    val mthToName : mth -> Date.month
    val mthFromName : Date.month -> mth

    val genDate : day * mth * year -> Date.date

    val now_local : unit -> Date.date
    val now_univ  : unit -> Date.date

    (* Misc Operations *)
    val leap : year -> bool
    val preceedingLeaps : year -> int
    val daysInMonth : year -> mth -> int
    val dateOk : day * mth * year -> bool
    val preceedingDays : day * mth * year -> int
    val currDateInPeriod : Date.date * Date.date -> bool
    val half_year        : Date.date -> Date.date * Date.date
    val add_days         : Date.date -> int -> Date.date

    (* PrettyPrinting *)
    val wrapOpt : ('a -> string) -> 'a option -> string
    val ppIso : Date.date -> string
    val ppDk  : Date.date -> string
    val ppLongDk  : Date.date -> string
    val ppLongEng : Date.date -> string
    val pp    : Date.date -> string
    val ppDb  : Date.date option -> string
    val ppTimestamp : Date.date -> string
  end

structure ScsDate :> SCS_DATE =
  struct
    exception ScsDate of string
    type day = int
    type mth = int
    type year = int
    type hour = int
    type sec = int

    fun mthToName mth =
      case mth of
	1 => Date.Jan
      | 2 => Date.Feb
      | 3 => Date.Mar
      | 4 => Date.Apr
      | 5 => Date.May
      | 6 => Date.Jun
      | 7 => Date.Jul
      | 8 => Date.Aug
      | 9 => Date.Sep
      | 10 => Date.Oct
      | 11 => Date.Nov
      | 12 => Date.Dec
      | _ => raise ScsDate ("Wrong month: " ^ (Int.toString mth))

    fun mthFromName mth =
      case mth of
	Date.Jan => 1
      | Date.Feb => 2
      | Date.Mar => 3
      | Date.Apr => 4
      | Date.May => 5
      | Date.Jun => 6
      | Date.Jul => 7
      | Date.Aug => 8
      | Date.Sep => 9
      | Date.Oct => 10
      | Date.Nov => 11
      | Date.Dec => 12

    fun now_local () = Date.fromTimeLocal(Time.now())
    fun now_univ () = Date.fromTimeUniv(Time.now())

    fun genDate (d,m,y) =
      Date.date{year=y,month=mthToName m,day=d,hour=0,minute=0,second=0,offset=NONE}
      handle Date.Date => raise ScsDate ("Wrong date: " ^ (Int.toString y) ^ "-" ^ (Int.toString m) ^ "-" ^ (Int.toString d))

    fun leap y = (Int.mod(y,4) = 0 andalso Int.mod(y,100) <> 0) orelse Int.mod(y,400) = 0

    (* Return the number of leap years since year 0 and before year y *)
    fun preceedingLeaps y =
      if y = 0 then 
	0 
      else 
	let
	  val y = y - 1
	in
	  Int.div(1 + y,4) - Int.div(y,100) + Int.div(y,400)
	end

    (* Return the number of days in a given month *)
    fun daysInMonth y m =
      case m of
	1 => 31
      | 2 => if leap y then 29 else 28
      | 3 => 31
      | 4 => 30
      | 5 => 31
      | 6 => 30
      | 7 => 31
      | 8 => 31
      | 9 => 30
      | 10 => 31
      | 11 => 30
      | 12 => 31
      | _ => raise ScsDate ("Month " ^ (Int.toString m) ^ " does not exists.")


    (* Pretty Printing *)
    fun wrapOpt f dOpt =
      case dOpt of
	NONE => ""
      | SOME d => f d 

    val ppIso = Date.fmt "%Y-%m-%d"
    val ppDk  = Date.fmt "%d/%m-%Y"

    fun ppMthDk d =
      case Date.month d of
	Date.Jan => "januar"
      | Date.Feb => "februar"
      | Date.Mar => "marts"
      | Date.Apr => "april"
      | Date.May => "maj"
      | Date.Jun => "juni"
      | Date.Jul => "juli"
      | Date.Aug => "august"
      | Date.Sep => "september"
      | Date.Oct => "oktober"
      | Date.Nov => "november"
      | Date.Dec => "december"

    fun ppMthEng d =
      case Date.month d of
	Date.Jan => "January"
      | Date.Feb => "February"
      | Date.Mar => "Marts"
      | Date.Apr => "April"
      | Date.May => "May"
      | Date.Jun => "June"
      | Date.Jul => "July"
      | Date.Aug => "August"
      | Date.Sep => "September"
      | Date.Oct => "October"
      | Date.Nov => "November"
      | Date.Dec => "December"

    fun ppLongDk d = (Int.toString (Date.day d)) ^ ". " ^(ppMthDk d) ^ " " ^ (Date.fmt "%Y" d)

    fun ppLongEng d = (Int.toString (Date.day d)) ^ " " ^(ppMthEng d) ^ " " ^ (Date.fmt "%Y" d)
      
    fun pp s = 
      case ScsLogin.user_lang of
	ScsLang.da => ppDk s
      | ScsLang.en => ppIso s

    fun ppTimestamp s = Date.fmt "%H:%M.%S" s ^ " " ^ pp s

    fun ppDb s =
      case s
	of SOME d => pp d
      | _ => ""

    fun dateOk (d,m,y) =
      m >= 1 andalso m <= 12 andalso d >= 1 andalso d <= daysInMonth y m

    (* Given a date (d,m,y), return the number of days since 01.01.0000 *)
    fun preceedingDays (d,m,y) =
      let
	(* days in last month *)
	val days = d - 1
	(* days in preceeding months *)
	val mm = m - 1
	fun loop (0,acc) = acc
	  | loop (mm,acc) = loop (mm-1,acc + daysInMonth y mm)
	val days = loop (mm,days)
	(* days in preceeding years *)
	val days = 365 * y + preceedingLeaps y
      in
	days
      end

    fun currDateInPeriod (start_date, end_date) =
      let
	val curr_date = now_local()
      in
	if Date.compare(curr_date,start_date) = General.LESS orelse 
	  Date.compare(end_date,curr_date) = General.LESS then
	  false
	else
	  true
      end

    fun add_days d n =
      Date.fromTimeLocal (Time.+ (Time.fromSeconds(n * 24 * 3600),Date.toTime d))
      handle _ => raise ScsDate ("add_days: can't add " ^ (Int.toString n) ^ " days to the date " ^ (ppIso d))

    fun half_year d =
      let
	val year = Date.year d
	val p_first = genDate(1,1,year)
	val p_mid = genDate(30,6,year)
	val p_end = genDate(31,12,year)
      in
	case Date.compare (d,p_mid) of
	  LESS => (p_first,p_mid)
	| EQUAL => (p_first,p_mid)
	| GREATER => (add_days p_mid 1,p_end)
      end
  end

