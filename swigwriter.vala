/* Copyleft 2009-2010 -- pancake // nopcode.org */

using Vala;

public class SwigWriter : CodeVisitor {
	public bool pkgmode;
	public string pkgname;
	public bool show_externs;
	public bool glib_mode;
	public bool cxx_mode;
	public string[] files;
	public GLib.List<string> includefiles;
	public GLib.List<Method> methods;
	private CodeContext context;
	private FileStream? stream;
	private string classname;
	private string classcname;
	private string externs;
	private string statics;
	private string extends;
	private string enums;
	private string vectors;
	private string nspace;
	private string modulename;

	public SwigWriter (string name) {
		enums = "";
		statics = "";
		externs = "";
		extends = "";
		vectors = "";
		classname = "";
		this.modulename = name;
		this.includefiles = new GLib.List<string>();
	}

	private string get_alias (string name) {
		string oname = name;
		switch (name) {
/*
		case "use":
			return "_use";
*/
		case "cmd":
			name = "_cmd";
			break;
		case "def":
			name = "_def";
			break;
		case "print":
			name = "_print";
			break;
		case "del":
			name = "_del";
			break;
		case "from":
			name = "_from";
			break;
		case "continue":
			name = "cont";
			break;
		}
		if (name != oname)
			SwigCompiler.warning ("%s.%s method renamed to %s.%s".printf (
				classname, oname, classname, name));
		return name;
	}

	private string get_ctype (string _type) {
		string type = _type;
		string? iter_type = null;
		if (type == "null")
			SwigCompiler.error ("Cannot resolve type");
		if (type.has_prefix (nspace))
			type = type.substring (nspace.length) + "*";
		if (type.str (".") != null)
			type = type.replace (".", "");
		if (is_generic (type)) {
			iter_type = type.str ("<");
			iter_type = iter_type.replace ("<", "");
			iter_type = iter_type.replace (">", "");
			iter_type = iter_type.replace (nspace, "");
			type = type.split ("<", 2)[0];
		}
		type = type.replace ("?","");

		switch (type) {
		case "const gchar*":
			return "const char*";
		case "G": /* generic type :: TODO: review */
		case "gconstpointer":
		case "gpointer":
	 		return "void*";
		case "gdouble":
			return "double";
		case "gfloat":
			return "float";
		case "ut8":
		case "uint8":
		case "guint8":
			return "unsigned char";
		case "gchar**":
			return "char **";
		case "gchar":
			return "char";
		case "gchar*":
		case "string":
			return "char *"; // ??? 
		case "gint":
	 		return "int";
		case "glong":
	 		return "long";
		case "st64":
		case "int64":
		case "gint64":
			return "long long";
		case "ut64":
		case "uint64":
		case "guint64":
			return "unsigned long long";
		/* XXX swig does not support unsigned char* */
		case "uint8*":
		case "guint8*":
			return "unsigned char*";
		case "guint16":
		case "uint16":
			return "unsigned short";
		case "ut32":
		case "uint32":
		case "guint32":
			return "unsigned int";
		case "bool": // no conversion needed
		case "gboolean":
			return "bool"; // XXX bool?
		case "RFList":
			if (iter_type != null)
				return "std::vector<"+iter_type+">";
			break;
		case "RList":
			if (iter_type != null)
				return "std::vector<"+iter_type+">";
			break;
		}
		return type;
	}

	private bool is_target_file (string path) {
		foreach (var file in files)
			if (file == path)
				return true;
		return false;
	}

	public override void visit_source_file (SourceFile source) {
		if (is_target_file (source.filename))
			source.accept_children (this);
	}

	public void process_includes (Symbol s) {
		foreach (var foo in s.get_cheader_filenames ()) {
			var include = true;
			foreach (var inc in includefiles) {
				if (inc == foo) {
					include = false;
					break;
				}
			}
			if (include)
				includefiles.prepend (foo);
		}
	}

	public void walk_field (Field f) {
		if (f.get_ctype () == null)
			SwigCompiler.warning (
				"Cannot resolve type for field '%s'".printf (f.get_cname ()));
		//if (f.access == Accessibility.PRIVATE)
		//	print ("---> field is private XXX\n");
		if (f.no_array_length)
			print ("---> array without length\n");
	}

	public void walk_class (string pfx, Class c) {
		foreach (var k in c.get_classes ())
			walk_class (c.name, k);
		classname = pfx+c.name;
		classcname = c.get_cname ();
		process_includes (c);
		if (glib_mode) {
			classname = "%s%s".printf (nspace, classname);
			extends += "typedef struct _%s {\n%%extend {\n".printf (classcname);
		} else extends += "%%extend %s {\n".printf (classname);
		foreach (var e in c.get_enums ())
			walk_enum (e);
		foreach (var f in c.get_fields ())
			walk_field (f);
		string? freefun = c.get_free_function ();
		if (freefun != null)
			extends += "  ~%s() {\n    %s (self);\n  }\n".printf (classname, freefun);
		foreach (var m in c.get_methods ())
			walk_method (m);
		if (glib_mode) extends += "};\n} %s;\n".printf (classname);
		else extends += "};\n";
		classname = "";
	}

	public void walk_enum (Vala.Enum e) {
		var enumname = classname + e.name;
		var tmp = "%{\n";
		enums += "/* enum: %s (%s) */\n".printf (
			e.name, e.get_cname ());
		enums += "enum %s {\n".printf (enumname);
		tmp += "#define %s long int\n".printf (enumname); // XXX: Use cname?
		foreach (var v in e.get_values ()) {
			enums += "  %s_%s,\n".printf (e.name, v.name);
			tmp += "#define %s_%s %s\n".printf (e.name, v.name, v.get_cname ());
		}
		enums += "};\n";
		enums += tmp + "%}\n";
	}

	private inline bool is_generic(string type) {
		return (cxx_mode && type.str ("<") != null && type.str (">") != null);
	}

	public void walk_method (Method m) {
		bool first = true;
		string cname = m.get_cname ();
		string alias = get_alias (m.name);
		string ret;
		string def_args = "";
		string call_args = "";
		bool void_return;
		bool is_static = (m.binding & MemberBinding.STATIC) != 0;
		bool is_constructor = (m is CreationMethod);

		// TODO: Implement contractual support
		// m.get_preconditions ();
		// m.get_postconditions ();

		ret = m.return_type.to_string ();
		if (is_generic (ret)) ret = get_ctype (ret);
		else ret = get_ctype (m.return_type.get_cname ());
		if (ret == null)
			SwigCompiler.error ("Cannot resolve return type for %s\n".printf (cname));
		void_return = (ret == "void");

		if (m.is_private_symbol ())
			return;

		string applys = "";
		string clears = "";
		string pfx;
		foreach (var foo in m.get_parameters ()) {
			string arg_name = foo.name;
			//DataType? bar = foo.parameter_type;
			DataType? bar = foo.variable_type;
			if (bar == null)
				continue;
			string? arg_type = get_ctype (bar.get_cname ());

			if (first) {
				pfx = "";
				first = false;
			} else pfx = ", ";

			/* TODO: move to get_ctype */
			if (foo.direction != ParameterDirection.IN) {
				var var_name = "";
				if (foo.direction == ParameterDirection.OUT)
					var_name = "OUTPUT";
				else
				if (foo.direction == ParameterDirection.REF)
					var_name = "INOUT";

				if (arg_type.str ("*") == null)
					arg_type += "*";
				applys += "  %%apply %s %s { %s %s };\n".printf (
					arg_type, var_name, arg_type, arg_name);
				clears += "  %%clear %s %s;\n".printf (arg_type, arg_name);
			}
			call_args += "%s%s".printf (pfx, arg_name);
			def_args += "%s%s %s".printf (pfx, arg_type, arg_name);
		}

		/* object oriented shit */
		if (classname == "") {
			externs += "extern %s %s (%s);\n".printf (ret, cname, def_args);
		} else {
			if (is_constructor) {
				externs += "extern %s* %s (%s);\n".printf (classcname, cname, def_args);
				extends += applys;
				extends += "  %s (%s) {\n".printf (classname, def_args);
				if (glib_mode)
					extends += "    g_type_init ();\n";
				extends += "    return %s (%s);\n  }\n".printf (cname, call_args);
				extends += clears;
			} else {
				if (is_static)
					statics += "extern %s %s (%s);\n".printf (ret, cname, def_args);
				else {
					if (call_args == "")
						call_args = "self";
					else call_args = "self, " + call_args;
				}
				externs += "extern %s %s (%s*, %s);\n".printf (ret, cname, classname, def_args);
				extends += applys;
				if (is_static)
					extends += "  static %s %s (%s) {\n".printf (ret, alias, def_args);
				else extends += "  %s %s (%s) {\n".printf (ret, alias, def_args);
				if (cxx_mode && ret.str ("std::vector") != null) {
					string iter_type;
					iter_type = ret.str ("<");
					iter_type = iter_type.replace ("<", "");
					iter_type = iter_type.replace (">", "");
					// TODO: Check if iter type exists before failing
					//       instead of hardcoding the most common type '<G>'
					// TODO: Do not construct a generic class if not supported
					//       instead of failing.
					if (iter_type == "G*") /* No generic */
						SwigCompiler.error ("Fuck, no <G> type support.\n");
					// TODO: Do not recheck the return_type
					if (m.return_type.to_string ().str ("RFList") != null) {
						extends += "    %s ret;\n".printf (ret);
						extends += "    void** array;\n";
						extends += "    %s *item;\n".printf (iter_type);
						extends += "    array = %s (%s);\n".printf (cname, call_args);
						extends += "    r_flist_rewind (array);\n";
						extends += "    while (*array != 0 && (item = (%s*)(*array++)))\n".printf (iter_type);
						extends += "        ret.push_back(*item);\n";
						extends += "    return ret;\n";
						extends += "  }\n";
					} else if (m.return_type.to_string ().str ("RList") != null) {
						extends += "    %s ret;\n".printf (ret);
						extends += "    RList *list;\n";
						extends += "    RListIter *iter;\n";
						extends += "    %s *item;\n".printf (iter_type);
						extends += "    list = %s (%s);\n".printf (cname, call_args);
						extends += "    for (iter = list->head; iter && (item = (%s*)iter->data); iter = iter->n)\n".printf (iter_type);
						extends += "        ret.push_back(*item);\n";
						extends += "    return ret;\n";
						extends += "  }\n";
					}
					vectors += "  %%template(%sVector) std::vector<%s>;\n".printf (
							iter_type, iter_type);
				} else {
					extends += "    %s %s (%s);\n  }\n".printf (
							void_return?"":"return", cname, call_args);
				}
				extends += clears;
			}
		}
	}

	public override void visit_namespace (Namespace ns) {
		if (ns.name == null)
			return;

		SourceReference? sr = ns.source_reference;
		if (sr != null && !is_target_file (sr.file.filename))
			return;

		nspace = ns.name;
		process_includes (ns);

		if (pkgmode && sr.file.filename.str (pkgname) == null)
			return;
		foreach (var f in ns.get_fields ())
			walk_field (f);
		foreach (var e in ns.get_enums ())
			walk_enum (e);
		foreach (var c in ns.get_structs ()) {
			/* TODO: refactor to walk_struct */
			foreach (var m in c.get_methods ())
				walk_method (m);
			foreach (var f in c.get_fields ())
				walk_field (f);
		}
		foreach (var m in ns.get_methods ())
			walk_method (m);
		foreach (var c in ns.get_classes ())
			walk_class ("", c);
		//ns.accept_children (this);
	}

	public void write_file (CodeContext context, string filename) {
		this.stream = FileStream.open (filename, "w");
		if (this.stream == null)
			error ("Cannot open %s for writing".printf (filename));
		this.context = context;
		context.accept (this);
		stream.printf ("%%module %s\n%%{\n", modulename);
		if (!cxx_mode) {
			stream.printf (
				"#define bool int\n"+
				"#define true 1\n"+
				"#define false 0\n");
		}
		if (includefiles.length () > 0) {
			if (cxx_mode)
				stream.printf ("extern \"C\" {\n");
			foreach (var inc in includefiles)
				stream.printf ("#include <%s>\n", inc);
			if (cxx_mode)
				stream.printf ("}\n#include <vector>\n");
		}
		stream.printf ("%%}\n");
		foreach (var inc in includefiles)
			stream.printf ("%%include <%s>\n", inc);
		if (cxx_mode) {
			stream.printf ("%%include \"std_vector.i\"\n\n");
			if (vectors != "")
				stream.printf ("namespace std {\n%s}\n", vectors);
		}

		stream.printf ("%s\n", enums);
		if (show_externs)
			stream.printf ("%s\n", externs);
		stream.printf ("%s\n", statics);
		stream.printf ("%s\n", extends);

		this.stream = null;
	}
}
