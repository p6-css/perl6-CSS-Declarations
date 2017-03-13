use v6;

class CSS::Declarations::Box {
    use CSS::Declarations:ver(v0.0.4 .. *);
    use CSS::Declarations::Units;
    my Int enum Edges is export(:Edges) <Top Right Bottom Left>;
    has Numeric $.top;
    has Numeric $.right;
    has Numeric $.bottom;
    has Numeric $.left = 0;
    has Numeric $.width = 595pt;
    has Numeric $.height = 842pt;

    has Array $!padding;
    has Array $!border;
    has Array $!margin;

    use CSS::Declarations::Font;
    has CSS::Declarations::Font $.font is rw handles <em ex>;
    has CSS::Declarations $.css;

    has Hash @.save;

    my subset BoundingBox of Str where 'content'|'border'|'margin'|'padding';

    submethod TWEAK(
        Numeric :$!top = $!height,
        Numeric :$!bottom = $!top - $!height,
        Numeric :$!right = $!left + $!width,
        Str :$style = '',
        Numeric :$em = 12pt,
        Numeric :$ex = 0.75 * $em,
    ) {
        $!css //= CSS::Declarations.new(:$style),
        $!font //= CSS::Declarations::Font.new: :$em, :$ex, :$!css;
    }

    multi method top { $!top }
    multi method top(BoundingBox $box) {
        self."$box"()[Top];
    }

    multi method right { $!right }
    multi method right(BoundingBox $box) {
        self."$box"()[Right];
    }

    multi method bottom { $!bottom }
    multi method bottom(BoundingBox $box) {
        self."$box"()[Bottom]
    }

    multi method left { $!left }
    multi method left(BoundingBox $box) {
        self."$box"()[Left]
    }

    multi method width { $!width }
    multi method width(BoundingBox $box) {
        my \box = self."$box"();
        box[Right] - box[Left]
    }

    multi method height { $!height }
    multi method height(BoundingBox $box) {
        my \box = self."$box"();
        box[Top] - box[Bottom]
    }

    method !length($v) {
        self.font.length($v);
    }

    method translate( \x = 0, \y = 0) {
        self.Array = [ $!top    + y, $!right + x,
                       $!bottom + y, $!left  + x ];
    }

    method !width($qty) {
        { :thin(1pt), :medium(2pt), :thick(3pt) }{$qty} // self!length($qty)
    }

    method widths(List $qtys) {
        [ $qtys.map: { self!width($_) } ]
    }

    method padding returns Array {
        $!padding //= $.enclose($.Array, self.widths($!css.padding));
    }
    method border returns Array {
        $!border //= $.enclose($.padding, self.widths($!css.border-width));
    }
    method margin returns Array {
        $!margin //= $.enclose($.border, self.widths($!css.margin));
    }

    method content returns Array { self.Array }

    method enclose(List $inner, List $outer) {
        [
         $inner[Top]    + $outer[Top],
         $inner[Right]  + $outer[Right],
         $inner[Bottom] - $outer[Bottom],
         $inner[Left]   - $outer[Left],
        ]
    }

    method css-height($css) {
        my Numeric $height = $_ with self!length($css.height);
        with self!length($css.max-height) {
            $height = $_
                if $height.defined && $height > $_;
        }
        with self!length($css.min-height) {
            $height = $_
                if $height.defined && $height < $_;
        }
        $height;
    }

    method css-width($css) {
        my Numeric $width = $_ with self!length($css.width);
        with self!length($css.max-width) {
            $width = $_
                if !$width.defined || $width > $_;
        }
        with self!length($css.min-width) {
            $width = $_
                if $width.defined && $width < $_;
        }
        $width;
    }

    method Array is rw {
        Proxy.new(
            FETCH => sub ($) {
                [$!top, $!right, $!bottom, $!left]
            },
            STORE => sub ($,@v) {
                $!padding = $!border = $!margin = Nil;
                $!top    = @v[Top] // 0;
                $!right  = @v[Right] // $!top;
                $!bottom = @v[Bottom] // $!top;
                $!left   = @v[Left] // $!right
            });
    }

    method build-box($css, &build-content) {
        my $top = self!length($css.top);
        my $bottom = self!length($css.bottom);
        my $left = self!length($css.left);
        my $right = self!length($css.right);
        my $width = self.css-width($css);
        my $height = self.css-height($css);

        my \height-max = do with $height {
            $_
        }
        else {
            my $max = $!height - ($top//0) - ($bottom//0);
            for <padding-top padding-bottom border-top-width border-bottom-width> {
                $max -= $_ with $css."$_"();
            }
            $max;
        }

        my \width-max = $width // do {
            my $max = $!width - ($left//0) - ($right//0);
            for <padding-left padding-right border-left-width border-right-width> {
                $max -= $_ with $css."$_"();
            }
            $max;
        }

        my ($type, $content) = (.key, .value)
            with &build-content( :width(width-max), :height(height-max) );

        $width //= width-max if $left.defined && $right.defined;
        $width //= $content.content-width;
        with self!length($css.min-width) -> \min {
            $width = min if min > $width
        }

        $height //= $content.content-height;
        with self!length($css.min-height) -> \min {
            $height = min if min > $height
        }

        my Bool \from-left = $left.defined;
        unless from-left {
            $left = $right.defined
                ?? $!width - $right - $width
                !! 0;
        }

        my Bool \from-top = $top.defined;
        unless from-top {
            $top = $bottom.defined
                ?? $!height - $bottom - $height
                !! 0;
        }

        #| adjust from PDF coordinates. Shift origin from top-left to bottom-left;
        my \pdf-top = $!height - $top;
        my \box = self.new: :$css, :$left, :top(pdf-top), :$width, :$height, :$.em, :$.ex, |($type => $content);

        # reposition to outside of border
        my Numeric @content-box[4] = box.Array.list;
        my Numeric @border-box[4]  = box.border.list;
        my \dx = from-left
               ?? @content-box[Left]  - @border-box[Left]
               !! @content-box[Right] - @border-box[Right];
        my \dy = from-top
               ?? @content-box[Top]    - @border-box[Top]
               !! @content-box[Bottom] - @border-box[Bottom];

        box.translate(dx, dy);
        box;
    }

    method save {
        my $em = $!font.em;
        my $ex = $!font.ex;
        my $font-weight = $!font.weight;
        @!save.push: {
            :$!width, :$!height, :$em, :$ex, :$font-weight,
        }
    }

    method restore {
        if @!save {
            with @!save.pop {
                $!width       = .<width>;
                $!height      = .<height>;
                $!font.em     = .<em>;
                $!font.ex     = .<ex>;
                $!font.weight = .<font-weight>;
            }
        }
    }

    method can(Str \name) {
       my @meth = callsame;
       unless @meth {
           given name {
               when /^ (padding|border|margin)'-'(top|right|bottom|left) $/ {
                   #| absolute positions
                   my Str $box = ~$0;
                   my UInt \edge = %( :top(Top), :right(Right), :bottom(Bottom), :left(Left) ){$1};
                   @meth.push: method { self."$box"()[edge] };
               }
               when /^ (padding|border|margin)'-'(width|height) $/ {
                   #| cumulative widths and heights
                   my Str $box = ~$0;
                   @meth.push: do given ~$1 {
                       when 'width'  { method { .[Right] - .[Left] with self."$box"() } }
                       when 'height' { method { .[Top] - .[Bottom] with self."$box"() } }
                   }
               }
           }
           self.^add_method(name, $_) with @meth[0];
       }
       @meth;
    }
    method dispatch:<.?>(\name, |c) is raw {
        self.can(name) ?? self."{name}"(|c) !! Nil
    }
    method FALLBACK(Str \name, |c) {
        self.can(name)
            ?? self."{name}"(|c)
            !! die die X::Method::NotFound.new( :method(name), :typename(self.^name) );
    }
}
