use v6;

#| management class for a set of CSS Properties
class CSS::Properties:ver<0.3.9> {

    use CSS::Module:ver(v0.4.6+);
    use CSS::Module::CSS3;
    use CSS::Writer:ver(v0.2.4+);
    use Color;
    use Color::Conversion;
    use CSS::Properties::Property;
    use CSS::Properties::Edges;
    use CSS::Properties::Units :Scale;
    my %module-metadata{CSS::Module};     # per-module metadata
    my %module-properties{CSS::Module};   # per-module property attributes

    # contextual variables
    has Any %!values;         # property values
    has Any %!default;
    has Array %!box;
    has Hash %!struct;
    has Bool %!important;
    my subset Handling of Str where 'initial'|'inherit';
    has Handling %!handling;
    has CSS::Module $.module = CSS::Module::CSS3.module; #| associated CSS module
    has @.warnings;
    has Bool $.warn = True;

    #| normalised point value
    class NumPt is Num does CSS::Properties::Units::Type["pt"] {};

    my subset ZeroHash of Hash where {
        # e.g. { :px(0) } === { :mm(0.0) }
        with .values[0] { $_ ~~ Numeric && $_ =~= 0 }
    };
    multi sub css-eqv(ZeroHash:D $a, ZeroHash:D $b) { True }
    multi sub css-eqv(Hash:D $a, Hash:D $b) {
	if +$a != +$b { return False }
        for $a.kv -> $k, $v {
            return False
                unless $b{$k}:exists && css-eqv($v, $b{$k});
	}
	True;
    }
    multi sub css-eqv(List:D $a, List:D $b) {
	if +$a != +$b { return False }
	for $a.kv -> $k, $v {
	    return False
		unless (css-eqv($v, $b[$k]));
	}
	True;
    }
    multi sub css-eqv(Numeric:D $a, Numeric:D $b) { $a == $b }
    multi sub css-eqv(Stringy $a, Stringy $b) { $a eq $b }
    multi sub css-eqv(Any $a, Any $b) is default {
        when $a.isa(Pair) { css-eqv( %$a, $b) }
        when $b.isa(Pair) { css-eqv( $a, %$b) }
        when !$a.defined && !$b.defined { True }
	default { False }
    }
    our sub measure($_,
                    Numeric :$em = 12,
                    Numeric :$ex = $em * 3/4,
                    Numeric :$vw,
                    Numeric :$vh) is export(:measure) {
        state %roles;
        when Numeric {
            my Str $units = .?type // 'pt';
            my Numeric $scale = do given $units {
                when 'em'   { $em }
                when 'ex'   { $ex }
                when 'vw'   { $vw // die 'Viewport width is unknown' }
                when 'vh'   { $vh // die 'Viewport height is unknown' }
                when 'vmin' { min($vw // die 'Viewport dimensions are unknown', $vh) }
                when 'vmax' { max($vw // die 'Viewport dimensions are unknown', $vh) }
                when 'percent' { 0 }
                default { Scale.enums{$units} }
            } // die "unknown units: $units";
            my $num = $_ // 0;
            NumPt.new($num * $scale);
        }
        default { Nil }
    }

    sub make-property(CSS::Module $m, Str $name) {
        %module-properties{$m}{$name} //= do with %module-metadata{$m}{$name} -> %defs {
            with %defs<edges> {
                # e.g. margin, comprised of margin-top, margin-right, margin-bottom, margin-left
                for .list -> $side {
                    # these shouldn't nest or cycle
                    %defs{$side} = $_ with make-property($m, $side);
                }
                CSS::Properties::Edges.new( :$name, |%defs);
            }
            else {
                CSS::Properties::Property.new( :$name, |%defs );
            }
        }
        else {
            die "unknown property: $name"
        }
    }

    #| return module meta-data for a property
    method info(Str $prop) {
        with %module-properties{$!module}{$prop} {
            $_;
        }
        else {
            make-property($!module, $prop);
        }
    }

    method !get-props(Str $prop-name, List $expr) {
        my @props;

        my @expr;
        for $expr.list {
            if $_ ~~ Pair|Hash && .keys[0] ~~ /^'expr:'(.*)$/ {
                # embedded property declaration
                @props.push: ~$0 => .values[0]
            }
            else {
                # filter out '/' operator, as in 'font:10pt/12pt times-roman'
                @expr.push: $_
                    unless $prop-name eq 'font' && .<op> eqv '/';
            }
        }

        @props.push: $prop-name => @expr
            if @expr;

        @props;
    }

    method !build-property($prop, $expr, :$important) {
        my \keyw = $expr[0]<keyw>;
        if keyw ~~ Handling {
            self.handling($prop) = keyw;
        }
        else {
            self."$prop"() = $expr;
            self.important($prop) = $_
                with $important;
        }
    }

    method !parse-style(Str $style) {
        my $rule = "declaration-list";
        my $actions = $!module.actions.new;
        $!module.grammar.parse($style, :$rule, :$actions)
            or die "unable to parse CSS style declarations: $style";
        @!warnings = $actions.warnings;
        if $!warn {
            note .message for @!warnings;
        }
        $/.ast.list
    }

    method !build-declarations(@declarations) {

        for @declarations {
            with .<property> -> \decl {
                with decl<expr> -> \expr {
                    my $important = True
                        if decl<prio> ~~ 'important';

                    self!build-property( .key, .value, :$important)
                        for self!get-props(decl<ident>, expr).list;
                }
            }
        }
    }

    submethod TWEAK( Str :$style, :$inherit = [], :$copy, :$declarations,
                     :$module, :$warn, # stop these leaking through to %props
                     *%props, ) {
        with $!module.property-metadata {
            %module-metadata{$!module} //= $_
        }
        else {
            die "module {$!module.name} lacks meta-data"
        };

        my @declarations = .list with $declarations;
        @declarations.append: self!parse-style($_) with $style;
        self!build-declarations(@declarations);
        self.inherit($_) for $inherit.list;
        self!copy($_) with $copy;
        self.set-properties(|%props);
    }

    method !box-value(Str $prop, List $edges) is rw {
	Proxy.new(
	    FETCH => -> $ {
                %!box{$prop} //= do {
                    my $n = 0;
                    my @bound;
                    @bound[$n++] := self!item-value($_)
                        for $edges.list;
                    @bound;
                }
            },
	    STORE => -> $, $v {
                with $v {
                    # expand and assign values to child properties
                    my @v = .isa(List) ?? .list !! $_;
                    @v[1] //= @v[0];
                    @v[2] //= @v[0];
                    @v[3] //= @v[1];

                    my $n = 0;
                    for $edges.list -> $prop {
                        %!values{$prop} = $_
                            with self!coerce( @v[$n++], :$prop )
                    }
                }
                else {
                    self.delete($prop);
                }
	    }
        );
    }

    method !struct-value(Str $prop, List $children) is rw {
	Proxy.new(
	    FETCH => -> $ {
                %!struct{$prop} //= do {
                    my $n = 0;
                    my %bound;
                    %bound{$_} := self."$_"()
                        for $children.list;
                    %bound;
                }
            },
	    STORE => -> $, $rval {
                my %vals;
                given $rval {
                    when Nil         { self.delete($prop); }
                    when Associative { %vals = .Hash; }
                    default {
                        with self.module.parse-property($prop, $_, :$!warn) -> $expr {
                            my @props = self!get-props($prop, $expr);
                            %vals{.key} = .value for @props;
                        }
                    }
                }

                for $children.list -> $prop {
                    with %vals{$prop}:delete {
                        self."$prop"() = $_
                            with self!coerce($_, :$prop);
                    }
                    else {
                        self.delete($prop);
                    }
	        }
                note "unknown child properties of $prop: {%vals.keys.sort}"
                    if %vals
            }
            );
    }

    method !metadata { %module-metadata{$!module} }
    #| return the default value for the property
    method !default($prop) {
        %!default{$prop} //= self!coerce( .<default>[1] )
            with self!metadata{$prop};
    }

    method !item-value(Str $prop) is rw {
        Proxy.new(
            FETCH => -> $ {
                with %!values{$prop} {
                    $_
                }
                elsif $prop ~~ /^'border-'[top|right|bottom|left]'-color'$/ {
                    self.?color;
                }
                elsif $prop eq 'text-align' {
                    %!values<direction> && self.direction eq 'rtl' ?? 'right' !! 'left';
                }
                else {
                    %!values{$prop} = self!default($prop)
                }
            },
            STORE => -> $,$v {
                if $v ~~ Nil {
                    self.delete($prop);
                }
                else {
                    %!values{$prop} = $_
                        with self!coerce( $v, :$prop );
                }
            }
        );
    }

    method !child-handling(List $children) is rw {
        Proxy.new(
            FETCH => -> $ { [&&] $children.map: { %!handling{$_} } },
            STORE => -> $, Str $h {
                %!handling{$_} = $h
                    for $children.list;
            });
    }

    #| return property value handling: 'initial', or 'inherit';
    method handling(Str $prop --> Handling) is rw {
        with self.info($prop) {
            .edges
                ?? self!child-handling( .edges )
                !! %!handling{$prop}
        }
    }

    method !child-importance(List $children) is rw {
        Proxy.new(
            FETCH => -> $ { [&&] $children.map: { %!important{$_} } },
            STORE => -> $, Bool $v {
                %!important{$_} = $v
                    for $children.list;
            });
    }

    #| return true of the property has the !important attribute
    method important(Str $prop) is rw {
        with self.info($prop) {
            .edges
                ?? self!child-importance( .edges )
                !! %!important{$prop}
        }
    }

    my subset ColorAST of Pair where {.key ~~ 'rgb'|'rgba'|'hsl'|'hsla'}

    multi method from-ast(ColorAST $v) {
        my @channels = $v.value.map: {self.from-ast: $_};
        my Color $color;
        my $type = $v.key;
        @channels.tail *= 256
            if $type ~~ 'rgba'|'hsla';
        if $type eq 'hsla' {
            # convert hsla color to rgba
            my $a = @channels.pop;
            my %rgb = hsl2rgb(@channels);
            $color .= new: |%rgb, :$a;
        }
        else {
            $color .= new: |($type => @channels);
        }

        $color does CSS::Properties::Units::Type[$type];
    }
    multi method from-ast(Pair $v is copy where .key eq 'keyw') {
        state %cache;
        if $v.value eq 'transparent' {
            $v = 'rgba' => INIT Color.new: :r(0), :g(0), :b(0), :a(0)
        }
        %cache{$v.value} //= $v.value but CSS::Properties::Units::Type[$v.key]
    }
    method !set-type(\v, \type) {
        v ~~ Color|Hash|Array
            ?? v does CSS::Properties::Units::Type[type]
            !! v but  CSS::Properties::Units::Type[type];
    }
    multi method from-ast(Pair $v) {
        my \r = self.from-ast( $v.value );
        r ~~ CSS::Properties::Units::Type
            ?? r
            !! self!set-type(r, $v.key);
    }
    multi method from-ast(List $v) {
        $v.elems == 1
            ?? self.from-ast( $v[0] )
            !! [ $v.map: { self.from-ast($_) } ];
    }
    #| { :int(42) } => :int(42)
    multi method from-ast(Hash $v where .keys == 1) {
        self.from-ast( $v.pairs[0] );
    }
    multi method from-ast($v) is default {
        $v
    }

    multi sub coerce-str(List $_) {
        .map({ coerce-str($_) // return }).join: ' ';
    }
    multi sub coerce-str($_) is default {
        .Str if $_ ~~ Str|Numeric && ! .can('type');
    }
    has %!prop-cache; # cache, for performance
    method !coerce($val, Str :$prop) {
        my \expr = do with $prop && coerce-str($val) {
            (%!prop-cache{$prop}{$_} //= $.module.parse-property($prop, $_, :$!warn))
        }
        else {
            $val;
        }
        self.from-ast(expr);
    }

    #| convert 0 .. 255  =>  0.0 .. 1.0. round to 2 decimal places
    sub alpha($a) {
        :num(($a * 100/256).round / 100);
    }

    multi method to-ast(Pair $v) { $v }

    multi method to-ast($v, :$get = True) is default {
        my $key = $v.?type if $get;
        my $val = do given $v {
            when Color {
                given .?type {
                    when 'hsl' {
                        my (\h, \s, \l) = $v.hsl;
                        [ :num(h), :percent(s), :percent(l) ];
                    }
                    when 'hsla' {
                        my (\h, \s, \l) = $v.hsl;
                        [ :num(h), :percent(s), :percent(l), alpha($v.a) ];
                    }
                    when 'rgba' {
                        my (\r, \g, \b, \a) = $v.rgba;
                        [ :num(r), :num(g), :num(b), alpha(a) ];
                    }
                    default {
                        $key //= 'rgb';
                        my (\r, \g, \b) = $v.rgb;
                        [ :num(r), :num(g), :num(b) ];
                    }
                }
            }
            when List  {
                .elems == 1
                    ?? self.to-ast( .[0] )
                    !! [ .map: { self.to-ast($_) } ];
            }
            default {
                $key
                    ?? self.to-ast($_, :!get)
                    !! $_;
            }
        }

        $key
            ?? ($key => $val)
            !! $val;
    }

    #| CSS conformant inheritance from the given parent declaration list. Note:
    #| - handling of 'initial' and 'inherit' in the child declarations
    #| - !important override properties in parent
    #| - not all properties are inherited. e.g. color is, margin isn't
    multi method inherit(Str $style) {
        my $css = $.new( :$.module, :$style);
        $.inherit($css);
    }
    multi method inherit(CSS::Properties $css) {
        for $css.properties -> \name {
            my \info = self.info(name);
            unless info.box {
                my $inherit = False;
                my $important = False;
                with self.handling(name) {
                    when 'initial' { %!values{name}:delete }
                    when 'inherit' { $inherit = True }
                }
                elsif $css.important(name) {
                    $inherit = True;
                    $important = True;
                }
                elsif info.inherit {
                    $inherit = True without %!values{name};
                }
                if $inherit {
                    %!values{name} = $css."{name}"();
                    self.important(name) = True
                        if $important;
                }
            }
        }
    }

    method !copy(CSS::Properties $css) {
        %!values{$_} = $css."$_"()
            for $css.properties;
    }

    #| set a list of properties as hash pairs
    method set-properties(*%props) {
        for %props.pairs.sort -> \p {
            if %module-metadata{$!module}{p.key} {
                self."{p.key}"() = $_ with p.value;
            }
            else {
                warn "unknown property/option: {p.key}";
            }
        }
        self;
    }

    #| create a deep copy of a CSS declarations object
    method clone(*%props) {
        my $obj = self.new( :copy(self), :$!module );
        $obj.set-properties(|%props);
        $obj;
    }

    # Avoid these serialization optimizations, which won't parse correctly:
    #     font: bold;
    #     font: bold Helvetica;
    # Need a font-size to disambiguate, e.g.:
    #     font: bold medium Helvetica;
    #     font: medium Helvetica;
    multi method optimizable('font', Set :$kids!
                              where <font-size font-family>.Set ⊈ $kids ) {
        False;
    }

    multi method optimizable(Str $, Set :$kids!) is default {
        +$kids >= 2;
    }

    method optimize( @ast ) {
        my %prop-ast;
        for @ast {
            next unless .key eq 'property';
            my %v = .value;
            %prop-ast{$_} = %v
                with %v<ident>:delete;
        }

        self!optimize-ast(%prop-ast);
        assemble-ast(%prop-ast);
    }

    has Array $!compound-properties;
    method !compound-properties {
        $!compound-properties //= [.keys.sort.grep: -> \k { .{k}<children> } with self!metadata];
    }

    method !optimize-ast( %prop-ast ) {
        my \metadata = self!metadata;
        my %edges;

        for %prop-ast.keys.sort -> \prop {
            # delete properties that match the default value
            my \info = self.info(prop);

            with %prop-ast{prop}<expr> {
                my \val = .[0];
                my \default = self.to-ast: self!default(prop);

                %prop-ast{prop}:delete
                    if (val.elems == 1
                        ?? css-eqv(val, default[0])
                        !! css-eqv(val, default));
            }
            %edges{info.edge}++ if info.edge;
        }

        # consolidate box properties with common values
        # margin-right: 1pt; ... margin-bottom: 1pt -> margin: 1pt
        for %edges.keys.sort -> $prop {
            # bottom up aggregation of edges. e.g. border-top-width, border-right-width ... => border-width
            my \info = self.info($prop);
            next unless info.box;
            my @edges;
            my @asts;
            for info.edges -> \side {
                with %prop-ast{side} {
                    @edges.push: side;
                    @asts.push: $_;
                }
                else {
                    last;
                }
            }

            if @asts > 1 && @asts.map( *<prio> ).unique == 1 {
                # consecutive edges present at the same priority; consolidate
                %prop-ast{$_}:delete for @edges;

                my constant DefaultIdx = [Mu, Mu, 0, 0, 1];
                @asts.pop
                    while +@asts > 1
                    && css-eqv( @asts.tail, @asts[ DefaultIdx[+@asts] ] );

                %prop-ast{$prop} = { :expr[ @asts.map: *<expr> ] };
                %prop-ast{$prop}<prio> = $_
                    with @asts[0]<prio>;
            }
        }
        for self!compound-properties.list -> \prop {
            # top-down aggregation of compound properties. e.g. border-width, border-style => border

            my @children = metadata{prop}<children>.list.grep: {
                %prop-ast{$_}:exists
            }

            next unless @children && $.optimizable(prop, :kids(@children.Set));

            # agregrate related children to a compound property, where possible.
            # -- if child properties are 'initial', or 'inherit', they all
            #    need to be present and the same
            # -- otherwise they need to all need to have or lack
            #    the !important indicator

            my %groups = @children.classify: {
                given %prop-ast{$_} {
                    when .<expr>.elems > 1      {'multi'}
                    when .<keyw> ~~ Handling    {.<keyw>}     # 'default', 'initial'
                    when .<prio> ~~ 'important' {'important'}
                    default {'normal'}
                }
            }

            # don't agregrate properties with a complex expression
            # eg. border-color: red green blue yellow;
            %groups<multi>:delete;

            #| find largest consolidation group
            my $group = do with %groups.pairs.sort(*.key).sort({+.value}).tail {
                .key
                    if + .value > 1;
            }

            with $group {
                # all of the same type
                given %groups{$_}.list -> @children {
                    when Handling {
                        %prop-ast{$_}:delete for @children;
                        %prop-ast{prop} = { :expr[ :keyw($_) ] };
                    }
                    when 'important'|'normal' {
                        my %ast = expr => [ @children.map: {
                            my \sub-prop = %prop-ast{$_}:delete;
                            'expr:'~$_ => sub-prop<expr>;
                        } ];
                        %ast<prio> = $_
                            when 'important';
                        %prop-ast{prop} = %ast;
                    }
                }
            }
        }
        %prop-ast;
    }

    sub assemble-ast(%prop-ast) {
        with %prop-ast<font> {
            # reinsert font '/' operator if needed...
            with .<expr> {
                # e.g.: font: italic bold 10pt/12pt times-roman;
                $_ = [ flat .map: { .key eq 'expr:line-height' ?? [ :op('/'), $_, ] !! $_ } ];
            }
        }

        #| assemble property list
        my @declaration-list = %prop-ast.keys.sort.map: -> \prop {
            my %property = %prop-ast{prop};
            %property.push: 'ident' => prop;
            %property;
        };

        :@declaration-list;
    }

    #| return an AST for the declarations.
    #| This more-or-less the inverse of CSS::Grammar::CSS3::declaration-list>
    #| and suitable for reserialization with CSS::Writer
    method ast(Bool :$optimize = True) {
        my %prop-ast;
        # '!important'
        for %!important.pairs {
            %prop-ast{.key}<prio> = 'important'
                if .value;
        }
        # 'initial', 'inherit'
        for %!handling.pairs {
            %prop-ast{.key}<expr> = [ :keyw(.value) ];
        }

        #| expressions
        for %!values.keys.sort -> \prop {
            with %!values{prop} -> \value {
                my \ast = self.to-ast: value;
                %prop-ast{prop}<expr> = [ ast ];
            }
        }

        self!optimize-ast(%prop-ast)
            if $optimize;

        assemble-ast(%prop-ast);
    }

    #| write a set of declarations. By default, it is formatted as a single-line,
    #| suited to an HTML inline-style (style attribute).
    method write(Bool :$optimize = True,
                 Bool :$terse = True,
                 Bool :$color-names = True,
                 |c) {
        my CSS::Writer $writer .= new( :$terse, :$color-names, |c);
        $writer.write: self.ast(:$optimize);
    }

    method Str { self.write }

    #| return all module properties
    method properties(:$all) {
        ($all ?? %module-metadata{$!module} !! %!values).keys.sort;
    }

    #| delete property values from the list of populated properties
    method delete(*@props) {
        for @props -> Str $prop {
            with self!metadata{$prop} {
                if .<box> {
                    $.delete($_) for .<edges>.list
                }
                if .<children> {
                    $.delete($_) for .<children>.list
                }
            }
            %!values{$prop}:delete;
        }
        self;
    }

    method dispatch:<.?>(\name, |c) is raw {
        self.can(name)
            ?? self."{name}"(|c)
            !! do with self!metadata{name} { self!value($_, name, |c) } else { Nil }
    }
    method !value($_, \name, |c) is rw {
        .<children>
            ?? self!struct-value(name, .<children>)
            !! ( .<box>
                     ?? self!box-value(name, .<edges>)
                     !! self!item-value(name)
                    )
    }
    method FALLBACK(Str \name, |c) is rw {
        with self!metadata{name} {
            self!value($_, name, |c)
        }
        else {
            die X::Method::NotFound.new( :method(name), :typename(self.^name) )
        }
    }
}