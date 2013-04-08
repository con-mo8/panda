use v6;
use Panda::Ecosystem;
use Panda::Fetcher;
use Panda::Builder;
use Panda::Tester;
use Panda::Installer;
use Shell::Command;
use JSON::Tiny;

sub tmpdir {
    state $i = 0;
    ".work/{time}_{$i++}"
}

class Panda {
    has $.ecosystem;
    has $.fetcher   = Panda::Fetcher;
    has $.builder   = Panda::Builder;
    has $.tester    = Panda::Tester;
    has $.installer = Panda::Installer;

    multi method announce(Str $what) {
        say "==> $what"
    }

    multi method announce('fetching', Panda::Project $p) {
        self.announce: "Fetching {$p.name}"
    }

    multi method announce('building', Panda::Project $p) {
        self.announce: "Building {$p.name}"
    }

    multi method announce('testing', Panda::Project $p) {
        self.announce: "Testing {$p.name}"
    }

    multi method announce('installing', Panda::Project $p) {
        self.announce: "Installing {$p.name}"
    }

    multi method announce('success', Panda::Project $p) {
        self.announce: "Successfully installed {$p.name}"
    }

    multi method announce('depends', Pair $p) {
        self.announce: "{$p.key.name} depends on {$p.value.join(", ")}"
    }

    method project-from-local($proj as Str) {
        if $proj.IO ~~ :d and "$proj/META.info".IO ~~ :f {
            my $mod = from-json slurp "$proj/META.info";
            $mod<source-url>  = $proj;
            return Panda::Project.new(
                name         => $mod<name>,
                version      => $mod<version>,
                dependencies => $mod<depends>,
                metainfo     => $mod,
            );
        }
        return False;
    }

    method install(Panda::Project $bone, $nodeps,
                   $notests, $isdep as Bool) {
        my $dir = tmpdir();
        self.announce('fetching', $bone);
        $.fetcher.fetch($bone.metainfo<source-url>, $dir);
        self.announce('building', $bone);
        $.builder.build($dir);
        unless $notests {
            self.announce('testing', $bone);
            $.tester.test($dir) unless $notests;
        }
        self.announce('installing', $bone);
        $.installer.install($dir);

        $.ecosystem.project-set-state(
            $bone,
            $isdep ?? Panda::Project::installed-dep
                   !! Panda::Project::installed);
        self.announce('success', $bone);

        rm_rf $dir;
    }

    method get-deps(Panda::Project $bone) {
        my @bonedeps = $bone.dependencies.grep(*.defined);
        return () unless +@bonedeps;
        self.announce('depends', $bone => @bonedeps);
        my @deps;
        for @bonedeps -> $dep {
            my $p = $.ecosystem.get-project($dep);
            @deps.push: self.get-deps($p), $p;
        }
        return @deps;
    }

    method resolve($proj as Str, Bool :$nodeps, Bool :$notests) {
        my $bone = $.ecosystem.get-project($proj)
                   or die "Project $proj not found in the ecosystem";
        unless $nodeps {
            my @deps = self.get-deps($bone).uniq;
            @deps.=grep: {
                $.ecosystem.project-get-state($_)
                    == Panda::Project::absent
            };
            self.install($_, $nodeps, $notests, 1) for @deps;
        }
        self.install($bone, $nodeps, $notests, 0);
    }
}

# vim: ft=perl6
