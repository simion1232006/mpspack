% PROBLEM - abstract class defining interfaces for Helmholtz/Laplace BVPs/EVPs

classdef problem < handle
  properties
    segs                    % array of handles of segments in problem
    doms                    % array of handles of domains in problem
    k                       % overall wavenumber
    A                       % BC inhomogeneity matrix (incl sqrt(w) quad wei)
    sqrtwei                 % row vec of sqrt of quadrature weights w
    bas                     % cell array of handles of basis sets in problem
    basnoff                 % dof index offsets for basis objs referred by bas
    N                       % total number of dofs in a problem
    co                      % basis coefficient (length N column vector)
  end
  
  methods % ------------------------------ methods common to problem classes
  
   function fillquadwei(pr)   % ............... fill quadrature weights vector
   % FILLQUADWEI - compute sqrt of bdry quadrature weights vector for a problem
      pr.sqrtwei = [];        % get ready to stack stuff onto it as a big row
      for s=pr.segs
        if s.bcside==0          % matching condition
          w = sqrt(s.w);
          pr.sqrtwei = [pr.sqrtwei, w, w];  % stack twice the seg M
        elseif s.bcside==1 | s.bcside==-1   % BC (segment dofs natural order)
          pr.sqrtwei = [pr.sqrtwei, sqrt(s.w)]; 
        end
      end
    end % func
    
    function [N noff] = setupbasisdofs(pr)
    % SETUPBASISDOFS - set up indices of all basis degrees of freedom in problem
    %
    %   [N noff] = SETUPBASISDOFS(pr) sets problem basis set handle list pr.bas,
    %     overall # dofs pr.N, and problem basis object dof offsets pr.basnoff.
    %     It returns the last two. This is a helper routine for problem classes.
    %
    %    See also PROBLEM
      pr.bas = {};
      for d=pr.doms                  % loop over domains gathering basis sets
        pr.bas = {pr.bas{:} d.bas{:}};
      end
      pr.bas = utils.unique(pr.bas); % keep only unique basis handle objects
      noff = zeros(1, numel(pr.bas));
      N = 0;                         % N will be total # dofs (cols of A)
      for i=1:numel(pr.bas)
        noff(i) = N; N = N + pr.bas{i}.Nf; % set up dof offsets of bases
      end
      pr.N = N; pr.basnoff = noff;   % store stuff as problem properties
      if isempty(pr.bas), fprintf('warning: no basis sets in problem!\n'); end
    end
    
    function A = fillbcmatrix(pr, opts) %...........make bdry mismatch matrix
    % FILLBCMATRIX - computes matrix mapping basis coeffs to bdry mismatch
    %
    %   A = FILLBCMATRIX(pr) returns the matrix mapping all basis degrees of
    %   freedom in the problem to all segment boundary or matching condition
    %   mismatch functions. With no output argument the answer is written to
    %   the problem's property A.
    %
    %   A = FILLBCMATRIX(pr, opts) allows certain options including:
    %   opts.doms: if present, restricts to contrib from only domain list doms.
    %   opts.trans: if present, gives translation applied to all segments before
    %    evaluation is done.
    %   opts.basobj: if present, basis objects (bas, basnoff) are read from
    %    problem or domain object basobj (which must have setupbasisdofs method)
    %    Note that in order to affect the problem segments they must be listed
    %    in some problem domain.
    %    (The above three are needed by blochmodeproblem)
    %
    %    Notes: faster version, based on basis dofs rather than domain dofs
      if nargin<2, opts=[]; end
      if ~isfield(opts, 'doms'), opts.doms = []; end
      if ~isfield(opts, 'trans'), trans = []; else trans = opts.trans; end
      if isempty(pr.sqrtwei), pr.fillquadwei; end
      if isfield(opts, 'basobj'), bob = opts.basobj; else bob = pr; end
      N = bob.setupbasisdofs;
      A = zeros(numel(pr.sqrtwei), N);       % A is zero when no basis influence
      m = 0;                                 % colloc index counter
      o = [];                                % opts to pass into basis.eval
      for s=pr.segs % ======== loop over segs
        % either use seg as target, or create a translated pointset (non-self):
        if isempty(trans), c = s; else c = pointset(s.x + trans, s.nx); end
        if s.bcside==0            % matching condition (2M segment dofs needed)
          ms = m + (1:2*size(s.x,1));     % 2M colloc indices for block row
          dp = s.dom{1}; dm = s.dom{2};   % domain handles on the + and - side
          for i=1:numel(bob.bas)           % all bases in problem or basis obj
            b = bob.bas{i};
            ns = bob.basnoff(i)+(1:b.Nf);     % dof indices for this bas
            talkp = utils.isin(b, dp.bas);   % true if this bas talks to + side
            talkm = utils.isin(b, dm.bas);   %                           - side
            if talkp ~= talkm                % talks to either one not both
              o.dom = dp; ind = 1;
              if talkm, o.dom = dm; ind = 2; end   % tell b.eval & a which side
              if isempty(opts.doms) | utils.isin(o.dom, opts.doms) % restrict?
                [Ab Abn] = b.eval(c, o);
                A(ms, ns) = repmat(pr.sqrtwei(ms).', [1 b.Nf]) .* [s.a(ind)*Ab; s.b(ind)*Abn]; % overwrite block, g stacked below f
              end
            elseif talkp & talkm             % bas talks to both (eg transm LP)
              o.dom = dp;
              if isempty(opts.doms) | utils.isin(o.dom, opts.doms) % restrict?
                [Ab Abn] = b.eval(c, o);  % + side contrib
                A(ms, ns) = repmat(pr.sqrtwei(ms).', [1 b.Nf]) .* [s.a(1)*Ab; s.b(1)*Abn]; % overwrite block, g stacked below f
              end
              o.dom = dm;
              if isempty(opts.doms) | utils.isin(o.dom, opts.doms) % restrict?
                [Ab Abn] = b.eval(c, o);  % - side contrib
                A(ms, ns) = A(ms, ns) + repmat(pr.sqrtwei(ms).', [1 b.Nf]) .* [s.a(2)*Ab; s.b(2)*Abn]; % add block
              end
            end
          end
            
        elseif s.bcside==1 | s.bcside==-1  % BC (M segment dofs, natural order)
          ind = (1-s.bcside)/2+1; % index 1,2 for which side the BC on (+,-)
          d = s.dom{ind};         % handle of domain on the revelant side
          ms = m+(1:size(s.x,1)); % colloc indices for this block row
          if isempty(opts.doms) | utils.isin(d, opts.doms) %restrict to domains?
            o = []; o.dom = d;      % b.eval may need to know in which domain
            for i=1:numel(bob.bas)   % all bases in problem or bas obj (not dom)
              b = bob.bas{i};      % (that's needed so i index reflects bob.bas)
              if utils.isin(b, d.bas)   % true if this bas talks to BC side
                if s.b==0               % only values needed, ie Dirichlet
                  Ablock = b.eval(c, o);
                  if s.a~=1.0, Ablock = s.a * Ablock; end
                else                    % Robin (includes Neumann)
                  [Ablock Anblock] = b.eval(c, o);
                  if s.a==0 & s.b==1.0  % Neumann
                    Ablock = Anblock;
                  else                  % Robin
                    Ablock = s.a*Ablock + s.b*Anblock;
                  end
                end
                A(ms,pr.basnoff(i)+(1:b.Nf)) = ...
                    repmat(pr.sqrtwei(ms).', [1 b.Nf]) .* Ablock; % write blk
              end
            end
          end
        end
        m = ms(end);                    % update counter in either case
      end % ================ loop over segs
      if nargout==0, pr.A = A; end     % this only stores internally if no outp
    end % func
    
    function [u di] = pointsolution(pr, p) % ...........eval soln on pointset
    % POINTSOLUTION - evaluate solution to a problem on a pointset, given coeffs
    %
    %  [u di] = pointsolution(pr, pts) returns array of values u, and
    %   optionally, domain index list di (integer array of same shape as u).
    %   Decisions about which domain a gridpoint is in are done using
    %   domain.inside, which may be approximate.
    %
    %   Notes: 1) changed to reference dofs via bases rather than domains.
    %   2) A separate routine should be written for evaluation of u, u_n on
    %   boundary.
    %
    % See also GRIDSOLUTION.
      di = NaN*zeros(size(p.x));                    % NaN indicates in no domain
      u = di;                                       % solution field
      for n=1:numel(pr.doms)
        d = pr.doms(n);
        ii = d.inside(p.x);
        di(ii) = n;
        u(ii) = 0;                           % accumulate contribs to u in dom
        opts.dom = d;                        % b.eval might need know which dom
        for i=1:numel(pr.bas)                % loop over all bases...
          b = pr.bas{i};
          if utils.isin(b, d.bas)            % this bas talks to current dom?
            Ad = b.eval(pointset(p.x(ii)), opts);
            co = pr.co(pr.basnoff(i)+(1:b.Nf)); % extract coeff vector for basis
            u(ii) = u(ii) + Ad * co;           % add contrib from this basis obj
          end
        end
      end
    end % func
    
    function [u gx gy di] = gridsolution(pr, o) % ......... eval soln on grid
    % GRIDSOLUTION - evaluate solution to a problem over a grid, given coeffs
    %
    %  [u gx gy di] = gridsolution(pr, opts) returns array of values u, and
    %   optionally, x- and y-grids (1d lists) gx, gy, and domain index list di
    %   (integer array of same shape as u). Decisions about which domain a
    %   gridpoint is in are done using domain.inside, which may be approximate.
    %
    % To do: * keep evalbases matrices Ad for later use, multiple RHS's etc.
    % * what if evalbases matrices too big to store, sum basis vals by hand?
    %
    % See also POINTSOLUTION, GRIDBOUNDINGBOX
      o = pr.gridboundingbox(o);
      gx = o.bb(1):o.dx:o.bb(2); gy = o.bb(3):o.dx:o.bb(4);  % plotting region
      [xx yy] = meshgrid(gx, gy); zz = xx + 1i*yy;  % keep zz rect array
      [u di] = pr.pointsolution(pointset(zz));
    end % func
    
    function o = gridboundingbox(pr, o)
    % GRIDBOUNDINGBOX - set default options giving grid spacing and bound box
    %
    %  This code was pulled from gridsolution so scattering class can access it
      if nargin<2, o = []; end
      if ~isfield(o, 'dx'), o.dx = 0.03; end    % default grid spacing
      if o.dx<=0, error('dx must be positive!'); end
      if ~isfield(o, 'bb')                      % default bounding box
        bb = [];
        for d=pr.doms
          bb = [bb; d.boundingbox];
        end
        o.bb([1 3]) = min(bb(:,[1 3]), [], 1);  % find box enclosing all BBs
        o.bb([2 4]) = max(bb(:,[2 4]), [], 1);
      end
      o.bb(1) = o.dx * floor(o.bb(1)/o.dx);         % quantize to grid through 0
      o.bb(3) = o.dx * floor(o.bb(3)/o.dx);         % ... make this optional?
    end
    
    function h = showbdry(pr)   % ........................ crude plot bdry
    % SHOWBDRY - shows boundary segments in a problem, with their natural sense
      h = domain.showsegments(pr.segs, ones(size(pr.segs)));
    end
    
    function h = showbasesgeom(pr)   % ................ crude plot bases geom
      pr.setupbasisdofs;
      for i=1:numel(pr.bas)
        opts.label = sprintf('%d', i);              % label by problem's bas #
        pr.bas{i}.showgeom(opts);
      end
    end
    
    function setoverallwavenumber(pr, k) % ................. overall k
    % SETOVERALLWAVENUMBER - set problem k, in each domain using refactive index
    %
    %  setoverallwavenumber(pr, k) propagates overall wavenumber k to each
    %   domain, and its basis sets. If a domain has refractive index n, then
    %   its wavenumber will become n^2 k.
      pr.k = k;
      for d=pr.doms
        d.k = d.refr_ind^2 * k;
         % do basis sets, if any, in each domain...
        for i=1:numel(d.bas), d.bas{i}.k = d.k; end
      end
    end
    
    % *** Methods to be written ........... ****
    [u un] = bdrysolution(pr, seg, pm) % ........... evaluate soln on a bdry
    
    
  end % methods
   
  methods (Abstract) % ------------------------------------------------- 
    % none
  end
end