$PRESETS = {
    # attract_mean, attract_std, minr_lower, minr_upper, maxr_lower, maxr_upper, friction, flat_force
    balanced:       {
        univ:  [9, 150, 1280, 720],
        rules: [-0.02, 0.06, 0.0, 20.0, 20.0, 70.0, 0.025, false]
    },
    custom:       {
        univ:  [6, 150, 1280, 720],
        rules: [-0.01, 0.06, 0.0, 20.0, 20.0, 40.0, 0.025, true ]
    },
    chaos:          {
        univ:  [6, 100, 1280, 720],
        rules: [0.02, 0.04, 0.0, 30.0, 30.0, 100.0, 0.01, false]
    },
    gliders:        {
        univ:  [6, 100, 1280, 720],
        rules: [0.0, 0.06, 0.0, 20.0, 10.0, 50.0, 0.1, true]
    },
    custom_gliders: {
        univ:  [5, 100, 1280, 720],
        rules: [0.0, 0.07, 0.0, 20.0, 20.0, 40.0, 0.05, true]
    },
    quiescence:     {
        univ:  [6, 100, 1280, 720],
        rules: [-0.02, 0.1, 10.0, 20.0, 20.0, 60.0, 0.1, false]
    },
    diverse:        {
        univ:  [12, 150, 1280, 720],
        rules: [-0.01, 0.04, 0.0, 20.0, 10.0, 60.0, 0.05, true]
    },
    homogeneity:    {
        univ:  [4, 150, 1280, 720],
        rules: [0.0, 0.04, 10.0, 10.0, 10.0, 80.0, 0.05, true]
    },
    clusters:{
        univ:  [6, 150, 1280, 720],
        rules: [0.02, 0.05, 0.0, 20.0, 20.0, 50.0, 0.05, false]
    }
}

def tick args
  preset = $PRESETS[:custom_gliders]

  args.state.universe ||= big_bang_2(args, preset)
  args.state.universe = big_bang_2(args, preset) if args.inputs.keyboard.key_down.space
  universe            = args.state.universe
  repopulate(universe, args) if args.inputs.keyboard.key_down.enter
  universe.toggle_wrap if args.inputs.keyboard.key_down.w
  universe.step
  universe.redraw
  args.outputs.labels << {x: 10, y: 30, text: "FPS: #{$gtk.current_framerate.to_s.to_i}", r: 255, g: 0, b: 0}
  args.outputs.labels << {x: 10, y: 60, text: "W", r: 255, g: 255, b: 255, a: 64} if universe.m_wrap == true
  args.outputs.background_color = [0, 0, 0]

  universe.local_particles(Particle.new({x: args.inputs.mouse.x, y: args.inputs.mouse.y}))
end

def big_bang_2(args, preset)
  wrap = false
  if args.state.universe
    wrap = args.state.universe.m_wrap
  end
  universe = Universe.new(*preset[:univ])
  universe.reseed(*preset[:rules])
  universe.m_wrap = wrap
  universe.step
  cam_x    = 1280 / 2
  cam_y    = 720 / 2
  cam_zoom = 1
  universe.zoom(cam_x, cam_y, cam_zoom)
  reset_static_sprites(universe)
  universe
end

def reset_static_sprites(universe)
  $args.outputs.static_sprites.clear
  $args.outputs.static_sprites << universe.draw
end

def repopulate(universe, args)
  universe.set_random_particles
  args.outputs.static_sprites.clear
  args.outputs.static_sprites << universe.draw
  universe.step
end

RADIUS   = 5.0
DIAMETER = 2.0 * RADIUS
R_SMOOTH = 2.0


class Universe

  attr_accessor :m_particles, :m_types, :m_rand_gen, :m_center_x, :m_center_y, :m_zoom, :m_attract_mean, :m_attract_std,
                :m_minr_lower, :m_minr_upper, :m_maxr_lower, :m_maxr_upper, :m_friction, :m_flat_force, :m_wrap,
                :m_width, :m_height, :m_bins, :m_bin_size_inv, :respawn_bias

  def initialize(num_types, num_particles, width, height)
    #declare ivars

    @m_particles    = []
    @m_types        = ParticleTypes.new
    @m_bins         = {}
    @m_bin_size_inv = 1.0 / width.greater(height)
    @spawn_cooldown = 10
    #Initialize everything
    @m_rand_gen = Random.new
    set_population(num_types, num_particles)
    set_size(width, height)
    @m_center_x     = @m_width * 0.5
    @m_center_y     = @m_height * 0.5
    @m_zoom         = 1.0
    @m_attract_mean = 0.0
    @m_attract_std  = 0.0
    @m_minr_lower   = 0.0
    @m_minr_upper   = 0.0
    @m_maxr_lower   = 0.0
    @m_maxr_upper   = 0.0
    @m_friction     = 0.0
    @m_flat_force   = false
    @m_wrap         = true
    @dynamic_spawn  = false
  end

  def reseed(attract_mean, attract_std, minr_lower, minr_upper, maxr_lower, maxr_upper, friction, flat_force)
    @m_attract_mean = attract_mean
    @m_attract_std  = attract_std
    @m_minr_lower   = minr_lower
    @m_minr_upper   = minr_upper
    @m_maxr_lower   = maxr_lower
    @m_maxr_upper   = maxr_upper
    @m_friction     = friction
    @m_flat_force   = flat_force
    set_random_types
    set_random_particles
  end

  def init_bin
    @m_bins = {}
    @m_particles.each do |p|
      bin_x, bin_y          = bin_dex(p.x, p.y)
      @m_bins[bin_x]        ||= {}
      @m_bins[bin_x][bin_y] ||= []
      @m_bins[bin_x][bin_y] << p
    end
  end

  def de_bin(p, prev_idx = nil)
    if prev_idx
      bin_x, bin_y = prev_idx
    else
      bin_x, bin_y = bin_dex(p.x, p.y)
    end
    raise "Illegal state! #{__LINE__}" unless @m_bins[bin_x]
    raise "Illegal state! #{__LINE__}" unless @m_bins[bin_x][bin_y]
    @m_bins[bin_x][bin_y].delete(p)
  end

  def re_bin(p)
    bin_x, bin_y          = bin_dex(p.x, p.y)
    @m_bins[bin_x]        ||= {}
    @m_bins[bin_x][bin_y] ||= []
    @m_bins[bin_x][bin_y] << p
  end

  def bin_dex(x, y)
    bin_x = (x * @m_bin_size_inv).to_i
    bin_y = (y * @m_bin_size_inv).to_i
    return bin_x, bin_y
  end

  def xed_nib(bin_x, bin_y)
    x = (bin_x + 0.5) / @m_bin_size_inv
    y = (bin_y + 0.5) / @m_bin_size_inv
    return x, y
  end

  def local_particles(p)
    #return @m_particles
    max_r = @m_types.m_max_max_r[p.type]
    [p.x - max_r, p.x, p.x + max_r].product([p.y - max_r, p.y, p.y + max_r]).flat_map do |xy|
      x      = xy[0]
      y      = xy[1]
      wx, wy = x, y
      if @m_wrap
        wx += @m_width if wx < 0
        wx -= @m_width if wx > @m_width
        wy += @m_height if wy < 0
        wy -= @m_height if wy > @m_height
      end
      out = [[wx, wy]]
      xs  = [wx]
      ys  = [wy]
      if x != wx
        xs << 0 if wx < @m_width / 2
        xs << @m_width if wx > @m_width / 2
      end
      if y != wy
        ys << 0 if wy < @m_height / 2
        ys << @m_width if wy > @m_height / 2
      end
      if y != wy || x != wx
        out = xs.flat_map do |xx|
          ys.map do |yy|
            [xx, yy]
          end
        end
      end
      out
    end.flat_map do |xy|
      bin_x, bin_y = bin_dex(*xy)
      # $args.outputs.lines << [p.x,p.y,*xed_nib(bin_x,bin_y),255,255,255]
      out = []
      if @m_bins[bin_x]
        out = @m_bins[bin_x][bin_y] || []
      end
      out
    end
  end

  def set_population(num_types, num_particles)
    @m_types.resize(num_types)
    @m_particles = (1..num_particles).map { Particle.new }
  end

  def set_size(width, height)
    @m_width  = width
    @m_height = height
  end

  def set_random_types
    rand_attr = RandomGaussian.new(@m_attract_mean, @m_attract_std)
    rand_minr = RandomUniformReal.new(@m_minr_lower, @m_minr_upper)
    rand_maxr = RandomUniformReal.new(@m_maxr_lower, @m_maxr_upper)
    (0...@m_types.size).each do |i|
      @m_types.m_col[i]                                                   = {}
      @m_types.m_col[i][:r], @m_types.m_col[i][:g], @m_types.m_col[i][:b] = hsv_to_rgb(i / @m_types.size, 1.0, (i % 2) * 0.5 + 0.5)
      (0...@m_types.size).each do |j|
        ij = i * @m_types.size + j
        ji = j * @m_types.size + i
        if i == j
          @m_types.m_attract[ij] = -rand_attr.rand(@m_rand_gen).abs
          @m_types.m_min_r[ij]   = DIAMETER
        else
          @m_types.m_attract[ij] = rand_attr.rand(@m_rand_gen)
          @m_types.m_min_r[ij]   = rand_minr.rand(@m_rand_gen).greater(DIAMETER)
        end
        @m_types.m_max_r[ij] = rand_maxr.rand(@m_rand_gen).greater(@m_types.m_min_r[ij])
        @m_types.m_min_r[ji] = @m_types.m_min_r[ij]
        @m_types.m_max_r[ji] = @m_types.m_max_r[ij]
      end
    end
    @m_bin_size_inv = 1.0 / @m_types.m_max_r.max
    (0...@m_types.size).each do |i|
      @m_types.m_max_max_r[i] = 0.0
      (0...@m_types.size).each do |j|
        ij                      = i * @m_types.size + j
        @m_types.m_max_max_r[i] = @m_types.m_max_max_r[i].greater(@m_types.m_max_r[ij])
      end
    end
    @respawn_bias = (0...@m_types.size).map { |_| 0 }
  end

  def set_random_particles
    rand_type = RandomUniformInt.new(0, @m_types.size - 1)
    rand_uni  = RandomUniformReal.new(0.0, 1.0)
    rand_norm = RandomGaussian.new(0.0, 1.0)
    @m_particles.each do |p|
      p.type                = rand_type.rand(@m_rand_gen)
      @respawn_bias[p.type] += 1
      p.x                   = (rand_uni.rand(@m_rand_gen)) * @m_width
      p.y                   = (rand_uni.rand(@m_rand_gen)) * @m_height
      p.vx                  = rand_norm.rand(@m_rand_gen) * 0.0
      p.vy                  = rand_norm.rand(@m_rand_gen) * 0.0
    end
    init_bin
  end

  def toggle_wrap
    @m_wrap = !@m_wrap
  end

  def step_forces
    @m_particles.each do |p|
      p__ti = p.type * @m_types.size
      local_particles(p).each do |q|
        next if p == q
        pq_ti = p__ti + q.type
        dx    = q.x - p.x
        dy    = q.y - p.y
        if @m_wrap
          if dx > @m_width * 0.5
            dx -= @m_width
          elsif dx < -@m_width * 0.5
            dx += @m_width
          end
          if dy > @m_height * 0.5
            dy -= @m_height
          elsif dy < -@m_height * 0.5
            dy += @m_height
          end
        end
        r2    = dx * dx + dy * dy
        min_r = @m_types.m_min_r[pq_ti]
        max_r = @m_types.m_max_r[pq_ti]
        next if r2 > max_r * max_r || r2 < 0.01
        r  = Math.sqrt(r2)
        dx /= r
        dy /= r
        if r > min_r
          if @m_flat_force
            f = @m_types.m_attract[pq_ti]
          else
            numer = 2.0 * (r - 0.5 * (max_r + min_r)).abs
            denom = max_r - min_r
            f     = @m_types.m_attract[pq_ti] * (1.0 - numer / denom)
          end
        else
          f = R_SMOOTH * min_r * (1.0 / (min_r + R_SMOOTH) - 1.0 / (r + R_SMOOTH));
        end
        p.vx += f * dx
        p.vy += f * dy
      end
    end
  end

  def step_motion
    @m_particles.each do |p|
      next if p.vx == 0 && p.vy == 0
      # Update position and velocity
      last_x, last_y = p.x, p.y
      p.x            += p.vx
      p.y            += p.vy
      p.vx           *= (1.0 - @m_friction)
      p.vy           *= (1.0 - @m_friction)
      p.vx           = 0 if p.vx.abs < 0.000001
      p.vy           = 0 if p.vy.abs < 0.000001
      if @m_wrap
        p.x += @m_width if p.x < 0.0
        p.x -= @m_width if p.x > @m_width
        p.y += @m_height if p.y < 0.0
        p.y -= @m_height if p.y > @m_height
      else
        if p.x <= RADIUS
          p.vx = -p.vx
          p.x  = RADIUS
        elsif p.x >= @m_width - RADIUS
          p.vx = -p.vx
          p.x  = @m_width - RADIUS
        end
        if p.y <= RADIUS
          p.vy = -p.vy
          p.y  = RADIUS
        elsif p.y >= @m_height - RADIUS
          p.vy = -p.vy
          p.y  = @m_height - RADIUS
        end
      end

      if bin_dex(p.x, p.y) != bin_dex(last_x, last_y)
        de_bin(p, bin_dex(last_x, last_y))
        re_bin(p)
      end
    end
  end

  def step_aging
    @m_particles.each do |p|
      if p.vx == 0 && p.vy == 0
        p.life     -= 1
        life_ratio = p.life / p.life_span
        p.sprite.a = 255 * life_ratio * life_ratio * life_ratio * life_ratio
      elsif p.life != p.life_span
        p.life     = p.life_span
        p.sprite.a = 255
      end
      if p.life == 0
        de_bin(p)
        if $gtk.current_framerate < 10
          @m_particles.delete(p)
          reset_static_sprites(self)
        else
          @respawn_bias.each_index do |i|
            @respawn_bias[i] = (@respawn_bias[i] - @m_types.size + 1).greater(0) if p.type == i
            @respawn_bias[i] += 1 unless p.type == i
          end
          bias_sum          = @respawn_bias.reduce(&:plus)
          respawn_intervals = @respawn_bias.reduce([[-1], 0]) do |acc, val|
            acc[1] += val / bias_sum
            (acc[0][0] == -1) ? acc[0] = [acc[1]] : acc[0] << acc[1]
            acc
          end[0]
          rand_uni          = RandomUniformReal.new(0.0, 1.0)
          rand_norm         = RandomGaussian.new(0.0, 1.0)

          # Roulette selection thing
          type_float = rand_uni.rand(@m_rand_gen)
          respawn_intervals.each_with_index do |v, i|
            if type_float < v
              p.type = i
              break
            end
          end
          cond = -1
          while cond < 0
            p.x  = (rand_uni.rand(@m_rand_gen)) * @m_width
            p.y  = (rand_uni.rand(@m_rand_gen)) * @m_height
            cond = @m_particles.map do |q|
              dx    = q.x - p.x
              dy    = q.y - p.y
              if @m_wrap
                if dx > @m_width * 0.5
                  dx -= @m_width
                elsif dx < -@m_width * 0.5
                  dx += @m_width
                end
                if dy > @m_height * 0.5
                  dy -= @m_height
                elsif dy < -@m_height * 0.5
                  dy += @m_height
                end
              end
              r2    = dx * dx + dy * dy
              min_r = @m_types.m_min_r[p.type * @m_types.size + q.type]
              max_r = @m_types.m_max_r[p.type * @m_types.size + q.type]

              if r2 == 0
                0
              else
                (r2 - min_r*min_r).lesser(max_r * max_r - r2)
              end
            end.max
          end
          p.vx = rand_norm.rand(@m_rand_gen) * 0.2
          p.vy = rand_norm.rand(@m_rand_gen) * 0.2
          re_bin(p)
        end
      end
    end
  end

  def step
    step_forces
    step_motion
    step_aging
    @spawn_cooldown = 10 if $gtk.current_framerate < 59
    if @spawn_cooldown == 0 && @dynamic_spawn
      @spawn_cooldown = 10
      rand_type       = RandomUniformInt.new(0, @m_types.size - 1)
      rand_uni        = RandomUniformReal.new(0.0, 1.0)
      rand_norm       = RandomGaussian.new(0.0, 1.0)
      p               = Particle.new
      p.type          = rand_type.rand(@m_rand_gen)
      p.x             = (rand_uni.rand(@m_rand_gen)) * @m_width
      p.y             = (rand_uni.rand(@m_rand_gen)) * @m_height
      p.vx            = rand_norm.rand(@m_rand_gen) * 0.0
      p.vy            = rand_norm.rand(@m_rand_gen) * 0.0
      @m_particles << p
      re_bin(p)
      reset_static_sprites(self)
    end
    @spawn_cooldown = (@spawn_cooldown - 1).greater(0)
  end

  def draw
    @m_particles.map do |p|
      x          = (p.x - @m_center_x) * @m_zoom + (@m_width / 2.0)
      y          = (p.y - @m_center_y) * @m_zoom + (@m_height / 2.0)
      color      = @m_types.m_col[p.type]
      p.sprite.x = x - RADIUS
      p.sprite.y = y - RADIUS
      p.sprite.w = DIAMETER
      p.sprite.h = DIAMETER
      p.sprite.r = color[:r]
      p.sprite.g = color[:g]
      p.sprite.b = color[:b]
      p.sprite
    end
  end

  def zoom(cx, cy, zoom)
    @m_zoom     = zoom.greater(1.0)
    h_inv_zoom  = 0.5 / @m_zoom
    @m_center_x = cx.clamp(@m_width * (1.0 - h_inv_zoom), @m_width * h_inv_zoom)
    @m_center_y = cy.clamp(@m_height * (1.0 - h_inv_zoom), @m_height * h_inv_zoom)
    redraw
  end

  def redraw
    hw = (@m_width / 2.0)
    hh = (@m_height / 2.0)
    @m_particles.each do |p|
      x          = (p.x - @m_center_x) * @m_zoom + hw
      y          = (p.y - @m_center_y) * @m_zoom + hh
      p.sprite.x = x - RADIUS * @m_zoom
      p.sprite.y = y - RADIUS * @m_zoom
      p.sprite.w = DIAMETER * @m_zoom
      p.sprite.h = DIAMETER * @m_zoom
    end
  end

  def get_index(x, y)
    cx, cy = to_center(x, y)
    (0..@m_particles.length - 1).each do |i|
      dx = @m_particles[i].x - cx
      dy = @m_particles[i].y - cy
      if dx * dx + dy * dy < RADIUS * RADIUS
        return i
      end
    end
    -1
  end

  def get_particle_x(index)
    @m_particles[index].x
  end

  def get_particle_y(index)
    @m_particles[index].y
  end

  def to_center(x, y)
    return @m_center_x + (x - @m_width / 2) / @m_zoom, @m_center_y + (y - @m_height / 2) / @m_zoom
  end

  def print_params

  end
end

class Particle
  attr_accessor :x, :y, :vx, :vy, :type, :sprite, :life, :life_span

  def initialize(params = {})
    @x         = params[:x] || 0.0
    @y         = params[:y] || 0.0
    @vx        = params[:vx] || 0.0
    @vy        = params[:vy] || 0.0
    @type      = params[:type] || 0
    @life_span = params[:life_span] || 60
    @life      = params[:life] || rand(@life_span)
    @sprite    = Sprite.new({
                                x:    @x - RADIUS,
                                y:    @y - RADIUS,
                                w:    DIAMETER,
                                h:    DIAMETER,
                                path: 'sprites/circle-white.png'
                            })
  end

  def to_hash
    {
        x:         @x,
        y:         @y,
        vx:        @vx,
        vy:        @vy,
        type:      @type,
        life:      @life,
        life_span: @life_span
    }
  end
end

class ParticleTypes
  attr_accessor :m_col, :m_attract, :m_min_r, :m_max_r, :m_max_max_r, :size

  def initialize
    @m_col       = []
    @m_attract   = []
    @m_min_r     = []
    @m_max_r     = []
    @m_max_max_r = []
    @size        = 0
  end

  def resize(size)
    @m_col       = (1..size).map { {r: 255, g: 255, b: 255} }
    @m_attract   = (1..size * size).map { 0.0 }
    @m_min_r     = (1..size * size).map { 0.0 }
    @m_max_r     = (1..size * size).map { 0.0 }
    @m_max_max_r = (1..size).map { 0.0 }
    @size        = size
  end
end

class RandomGaussian
  def initialize(mean = 0.0, sd = 1.0)
    @mean, @sd         = mean, sd
    @compute_next_pair = false
  end

  def rand(rng = Kernel)
    if (@compute_next_pair = !@compute_next_pair)
      # Compute a pair of random values with normal distribution.
      # See http://en.wikipedia.org/wiki/Box-Muller_transform
      theta = 2 * Math::PI * rng.rand
      scale = @sd * Math.sqrt(-2 * Math.log(1 - rng.rand))
      #scale = @sd * Math.sqrt(-2 * Math.log(1 - Kernel.rand))
      @g1 = @mean + scale * Math.sin(theta)
      @g0 = @mean + scale * Math.cos(theta)
    else
      @g1
    end
  end
end

class RandomUniformReal
  def initialize(min = 0.0, max = 1.0)
    @scale, @shift = max - min, min
  end

  def rand(rng = Kernel)
    rng.rand * @scale.to_f + @shift
    #Kernel.rand() * @scale + @shift
  end
end

class RandomUniformInt
  def initialize(min = 0, max = 1)
    @min = min
    @max = max - min + 1
  end

  def rand(rng = Kernel)
    #rng.rand(@max.to_i) + @min
    #(Kernel.rand * @max + @min).to_int
    (rng.rand * @max + @min).to_int
  end
end

class Sprite
  attr_sprite

  attr_accessor :x, :y, :w, :h, :path, :angle, :a, :r, :g, :b, :tile_x,
                :tile_y, :tile_w, :tile_h, :flip_horizontally,
                :flip_vertically, :angle_anchor_x, :angle_anchor_y, :id,
                :source_x, :source_y, :source_w, :source_h

  def initialize(params = {})
    @x    = params[:x] || -1
    @y    = params[:y] || -1
    @w    = params[:w] || 1
    @h    = params[:h] || 1
    @r    = params[:r] if params[:r] != nil
    @g    = params[:g] if params[:g] != nil
    @b    = params[:b] if params[:b] != nil
    @a    = params[:a] if params[:a] != nil
    @path = params[:sprite] || 'sprites/circle-white.png'
  end

  def primitive_marker
    :sprite
  end

  def sprite
    self
  end

  def x1
    @x
  end

  def x1= value
    @x = value
  end

  def y1
    @y
  end

  def y1= value
    @y = value
  end
end

# http://martin.ankerl.com/2009/12/09/how-to-create-random-colors-programmatically
def hsv_to_rgb(h, s, v)
  h_i     = (h * 6).to_i
  f       = h * 6 - h_i
  p       = v * (1 - s)
  q       = v * (1 - f * s)
  t       = v * (1 - (1 - f) * s)
  r, g, b = v, t, p if h_i == 0
  r, g, b = q, v, p if h_i == 1
  r, g, b = p, v, t if h_i == 2
  r, g, b = p, q, v if h_i == 3
  r, g, b = t, p, v if h_i == 4
  r, g, b = v, p, q if h_i == 5
  [(r * 255).to_i, (g * 255).to_i, (b * 255).to_i]
end