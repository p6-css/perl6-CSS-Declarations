use v6;
use Test;
plan 25;
use CSS::Properties;

my $inherit = CSS::Properties.new: :style("margin-top:5pt; margin-right: 10pt; margin-left: 15pt; margin-bottom: 20pt; color:rgb(0,0,255)!important");

is-deeply ($inherit.inherited), ('color',); 

my $css = CSS::Properties.new( :style("margin-top:25pt; margin-right: initial; margin-left: inherit"), :$inherit );

is-deeply ($css.inherited), ('color', 'margin-left'); 
is-deeply $css.inherited('margin-left'), True; 
is-deeply $css.inherited('margin-right'), False; 

nok $css.handling("margin-top"), 'overridden value';
is $css.margin-top, 25, "overridden value";

is $css.handling("margin-right"), "initial", "'initial'";
is $css.margin-right, 0, "'initial'";

is $css.handling("margin-left"), "inherit", "'inherit'";
is $css.margin-left, 15, "'inherit'";

is $css.info("color").inherit, True, 'color inherit metadata';
is $css.color, '#0000FF', "inheritable property";

is $css.info("margin-bottom").inherit, False, 'margin-bottom inherit metadata';
is $css.margin-bottom, 0, "non-inhertiable property";

$css = CSS::Properties.new( :style("margin: inherit"), :$inherit);
is $css.margin-top, 5, "inherited box value";
is $css.margin-right, 10, "inherited value";
is-deeply ($css.inherited), ("color", "margin-bottom", "margin-left", "margin-right", "margin-top");

$css = CSS::Properties.new( :style("margin: initial; color:purple"), :$inherit);
is $css.margin-top, 0, "initial box value";
is $css.color, '#7F007F', "inheritable !important property";
nok $css.important("color"), '!important is not inherited';

# inherit from css object
is ~$css, 'color:purple; margin-bottom:initial; margin-left:initial; margin-right:initial;', 'inherit from object';

# inherit from style string
$css = CSS::Properties.new( :inherit(~$inherit));
is ~$css, 'color:blue;', 'inherit from object';

$inherit = CSS::Properties.new: :style("font-size: 12pt;");
$css = CSS::Properties.new: :style("color:red"), :$inherit;
is ~$css, 'color:red; font-size:12pt;', 'inherit absolute font-size';

$inherit = CSS::Properties.new: :style("font-size: larger;");
$css = CSS::Properties.new: :style("color:red"), :$inherit;
is ~$css, 'color:red;', 'non-inheritance of relative font-size';

$inherit = CSS::Properties.new: :style("font-size: 1.5em;");
$css = CSS::Properties.new: :style("color:red"), :$inherit;
is ~$css, 'color:red;', 'non-inheritance of relative font-size';

done-testing;
