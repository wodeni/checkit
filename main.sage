from lxml import etree
import lxml.html
import os


# USAGE NOTE: If this script is loaded from another script/notebook
# located in a different directory, use the following pattern
# to ensure XSL files are imported correctly as well.
# oldwd=os.getcwd()
# try: os.chdir("path/to"); load("main.sage")
# finally: os.chdir(oldwd)
HTML_TRANSFORM = etree.XSLT(etree.parse(os.path.join("xsl", "html.xsl")))
LATEX_TRANSFORM = etree.XSLT(etree.parse(os.path.join("xsl", "latex.xsl")))
QTI_TRANSFORM = etree.XSLT(etree.parse(os.path.join("xsl", "qti.xsl")))


# XSL Helpers
def insert_object_into_element(obj, name, element):
    if obj is False:
        # skip generating element only when exactly False (not falsy)
        return None
    se = etree.SubElement(element, name)
    if isinstance(obj, list):
        for item in obj:
            insert_object_into_element(item, "item", se)
    elif isinstance(obj, dict):
        for key in obj.keys():
            insert_object_into_element(obj[key], key, se)
    else:
        if isinstance(obj, str):
            se.text = obj
        else:
            se.text = f" {latex(obj)} "


def dict_to_tree(data_dict):
    tree = etree.Element("data")
    for key in data_dict.keys():
        insert_object_into_element(data_dict[key], key, tree)
    return tree


# Generator helpers
def mi_vars(*latex_names, random_order=True):
    """
    Given one or more `latex_names` of strings, returns a tuple
    of Sage variables. `random_order` names them so that they appear
    in expressions in a random order.
    """
    stamp = randrange(100000, 999999)
    indices = list(range(len(latex_names)))
    if random_order:
        shuffle(indices)
    import string
    random_letter = choice(list(string.ascii_lowercase))
    return (var(f"{random_letter}_mi_var_{stamp}_{indices[i]}", latex_name=name) for i, name in enumerate(latex_names))


def shuffled_equation(*terms):
    """
    Represents the equation sum(terms)==0, but with terms shuffled randomly
    to each side.
    """
    new_equation = (SR(0) == 0)
    for term in terms:
        if choice([True, False]):
            new_equation += (SR(term) == 0)
        else:
            new_equation += (0 == -SR(term))
    return new_equation*choice([-1, 1])


def base64_graphic(obj, file_format="svg"):
    """
    Generates Base64 encoding of the graphic in the requested file_format.
    """
    if not isinstance(obj, Graphics):
        raise TypeError("Only graphics may be encoded as base64")
    if file_format not in ["svg", "png"]:
        raise ValueError("Invalid file format")
    filename = tmp_filename(ext=f'.{file_format}')
    obj.save(filename)
    with open(filename, 'rb') as f:
        from base64 import b64encode
        b64 = b64encode(f.read())
    return b64


def data_url_graphic(obj, file_format="svg"):
    """
    Generates Data URL representing the graphic in the requested file_format.
    """
    b64 = base64_graphic(obj, file_format=file_format).decode('utf-8')
    if file_format == "svg":
        file_format = "svg+xml"
    return f"data:image/{file_format};base64,{b64}"


def latex_system_from_matrix(matrix, variables="x", alpha_mode=False, variable_list=[]):
    # Augment with zero vector if not already augmented
    if not matrix.subdivisions()[1]:
        matrix = matrix.augment(zero_vector(
            ZZ, len(matrix.rows())), subdivide=true)
    num_vars = matrix.subdivisions()[1][0]
    # Start using requested variables
    system_vars = variable_list
    # Conveniently add xyzwv if requested
    if alpha_mode:
        system_vars += list(var("x y z w v"))
    # Finally fall back to x_n as needed
    system_vars += [var(f"{variables}_{n+1}") for n in range(num_vars)]
    # Build matrix
    latex_output = "\\begin{matrix}\n"
    for row in matrix.rows():
        if row[0] != 0:
            latex_output += latex(row[0]*system_vars[0])
            previous_terms = True
        else:
            previous_terms = False
        for n, cell in enumerate(row[1:num_vars]):
            latex_output += " & "
            if cell < 0 and previous_terms:
                latex_output += " - "
            elif cell > 0 and previous_terms:
                latex_output += " + "
            latex_output += " & "
            if cell != 0:
                latex_output += latex(cell.abs()*system_vars[n+1])
            if not previous_terms:
                previous_terms = bool(cell != 0)
        if not previous_terms:
            latex_output += " 0 "
        latex_output += " & = & "
        latex_output += latex(row[num_vars])
        latex_output += "\\\\\n"
    latex_output += "\\end{matrix}"
    return latex_output


# Exercise object
class Exercise:
    def __init__(self, title=None, slug=None, generator=None, template=None, seed=None):
        self.__title = title
        self.__slug = slug
        self.__generator = generator
        self.__template = template
        self.__seed = seed

    def data_dict(self):
        set_random_seed(self.__seed)
        return self.__generator()

    def data_tree(self):
        return dict_to_tree(self.data_dict())

    def template(self):
        PREFIX = """<?xml version="1.0"?>
<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output method="xml"/>
    <xsl:template match="/data">
"""
        SUFFIX = """
    </xsl:template>
</xsl:stylesheet>
"""
        return etree.XSLT(etree.XML(PREFIX+self.__template+SUFFIX))

    def pretext_tree(self):
        transform = self.template()
        tree = transform(self.data_tree()).getroot()
        tree.xpath("/*")[0].attrib['checkit-seed'] = f"{self.__seed:04}"
        tree.xpath("/*")[0].attrib['checkit-slug'] = str(self.__slug)
        tree.xpath("/*")[0].attrib['checkit-title'] = str(self.__title)
        return tree

    def pretext(self):
        return str(etree.tostring(self.pretext_tree(), pretty_print=True), encoding="UTF-8")

    def html_tree(self):
        transform = HTML_TRANSFORM
        tree = transform(self.pretext_tree()).getroot()
        return tree

    def html(self):
        return str(etree.tostring(self.html_tree(), pretty_print=True), 'UTF-8')

    def latex(self):
        transform = LATEX_TRANSFORM
        return str(transform(self.pretext_tree()))

    def qti_tree(self):
        transform = QTI_TRANSFORM
        tree = transform(self.pretext_tree()).getroot()
        for mattextxml in tree.xpath("//mattextxml"):
            mattext = etree.Element("mattext")
            mattext.attrib['texttype'] = 'text/html'
            mattext.text = lxml.html.tostring(lxml.html.fromstring(
                etree.tostring(mattextxml.find("*"), pretty_print=True)), pretty_print=True)
            mattextxml.addnext(mattext)
        return tree

    def qti(self):
        return str(etree.tostring(self.qti_tree(), pretty_print=True), 'UTF-8')

    def dict(self):
        return {
            "seed": self.__seed,
            "qti": self.qti(),
            "pretext": self.pretext(),
            "html": self.html(),
            "tex": self.latex(),
            "params": self.data_dict()
        }

    def preview(self):
        print("Data XML")
        print("-----------")
        print(str(etree.tostring(self.data_tree(), pretty_print=True), "UTF-8"))
        print()
        print("HTML source")
        print("-----------")
        print(self.html())
        print()
        print("LaTeX source")
        print("------------")
        print(self.latex())
        print()
        print("QTI source")
        print("------------")
        print(self.qti())
        print()
        print("PreTeXt source")
        print("------------")
        print(self.pretext())


# Exercises collection
class Outcome():
    def __init__(self, title=None, slug=None, generator=None, template=None, amount=50, fixed=False, public=False):
        self.__title = title
        self.__slug = slug
        self.__generator = generator
        self.__template = template
        if public:
            start = 0
            end = 1000
        else:
            start = 1000
            end = 10000
        if fixed:
            self.__seeds = list(range(start, start+amount))
        else:
            set_random_seed()
            self.__seeds = [randrange(start, end) for _ in range(amount)]

    def list(self):
        return [Exercise(self.__title, self.__slug, self.__generator, self.__template, seed) for seed in self.__seeds]

    def dict(self):
        return {
            "title": self.__title,
            "slug": self.__slug,
            "exercises": [e.dict() for e in self.list()],
        }

    def qtibank_generic_tree(self, bank_title):
        qtibank_tree = etree.fromstring("""<?xml version="1.0"?>
<questestinterop xmlns="http://www.imsglobal.org/xsd/ims_qtiasiv1p2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.imsglobal.org/xsd/ims_qtiasiv1p2 http://www.imsglobal.org/xsd/ims_qtiasiv1p2p1.xsd">
  <objectbank>
    <qtimetadata>
      <qtimetadatafield/>
    </qtimetadata>
  </objectbank>
</questestinterop>""")
        label = etree.SubElement(qtibank_tree.find("*/*/*"), "fieldlabel")
        label.text = "bank_title"
        entry = etree.SubElement(qtibank_tree.find("*/*/*"), "fieldentry")
        entry.text = f"{bank_title} -- {self.__slug}"
        return qtibank_tree

    def outcome_csv_row(self, count, bank_slug, oid_suffix):
        return [
            f"checkit_{bank_slug}_{count:02}_{self.__slug}_{oid_suffix:06}",
            "outcome",
            f"{count:02}-{self.__slug}: {self.__title}",
            "",
            self.__slug,
            "n_mastery",
            "2",
            "3",
            "4",
            "Exceeds Mastery",
            "3",
            "Meets Mastery",
            "2",
            "Near Mastery",
            "1",
            "Well Below Mastery",
            "0",
            "Insufficient Work to Assess",
        ]

    def build_files(
        self,
        build_path="__build__",
        bank_title="CheckIt Question Bank"
    ):
        # provision filesystem
        if not os.path.isdir(build_path):
            os.mkdir(build_path)
        outcome_build_path = os.path.join(build_path, self.__slug)
        if not os.path.isdir(outcome_build_path):
            os.mkdir(outcome_build_path)
        qtibank_build_path = os.path.join(build_path, "qti-bank")
        if not os.path.isdir(qtibank_build_path):
            os.mkdir(qtibank_build_path)
        print(f"Building {outcome_build_path}...")

        qtibank_tree = self.qtibank_generic_tree(bank_title)

        for count, seed in enumerate(self.__seeds):
            exercise = self.list()[count]
            # build flat files
            with open(f'{outcome_build_path}/{count:04}.ptx', 'w') as outfile:
                print(exercise.pretext(), file=outfile)
            with open(f'{outcome_build_path}/{count:04}.tex', 'w') as outfile:
                print(exercise.latex(), file=outfile)
            with open(f'{outcome_build_path}/{count:04}.html', 'w') as outfile:
                print(exercise.html(), file=outfile)
            with open(f'{outcome_build_path}/{count:04}.qti', 'w') as outfile:
                print(exercise.qti(), file=outfile)
            # add to qtibank file
            qtibank_tree.find("*").append(exercise.qti_tree())
            qtibank_tree.find("*").attrib['ident'] = self.__slug
        with open(f'{qtibank_build_path}/{self.__slug}.qti', 'w') as outfile:
            print(str(etree.tostring(qtibank_tree, encoding="UTF-8",
                                     xml_declaration=True, pretty_print=True), "UTF-8"), file=outfile)
        print(f"- Files built successfully!")


# Bank building
def build_bank(bank_path, amount=50, fixed=False, public=False):
    config = etree.parse(os.path.join(bank_path, "__bank__.xml"))
    bank_title = config.find("title").text
    bank_slug = config.find("slug").text
    # build Canvas outcome CSV
    outcome_csv = [[
        "vendor_guid",
        "object_type",
        "title",
        "description",
        "display_name",
        "calculation_method",
        "calculation_int",
        "mastery_points",
        "ratings",
    ]]
    # build JSON blob for bank
    bank_json = {
        "title": bank_title,
        "slug": bank_slug,
        "outcomes": [],
    }
    # Canvas chokes on repeated IDs from mult instructors in same institution
    import time
    oid_suffix = time.time()
    for n, objective in enumerate(config.xpath("objectives/objective")):
        slug = objective.find("slug").text
        title = objective.find("title").text
        oldwd = os.getcwd()
        os.chdir(bank_path)
        load(f"{slug}.sage")  # imports `generator` function
        os.chdir(oldwd)
        with open(os.path.join(bank_path, f"{slug}.ptx"), 'r') as template_file:
            template = template_file.read()
        outcome = Outcome(
            title=title,
            slug=slug,
            generator=generator,
            template=template,
            amount=amount,
            fixed=fixed,
            public=public,
        )
        outcome.build_files(
            build_path=os.path.join(bank_path, "__build__"),
            bank_title=bank_title,
        )
        bank_json["outcomes"].append(outcome.dict())
        outcome_csv.append(outcome.outcome_csv_row(n, bank_slug, oid_suffix))
    import csv
    with open(os.path.join(bank_path, "__build__", f"{bank_slug}-canvas-outcomes.csv"), 'w') as f:
        csv.writer(f).writerows(outcome_csv)
    print("Canvas outcomes built.")
    import json
    with open(os.path.join(bank_path, "__build__", f"{bank_slug}-bank.json"), 'w') as f:
        json.dump(bank_json, f)
    print("JSON blob built.")
    print("Bank build complete!")
